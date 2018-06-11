package PVE::APIClient::Commands::lxc;

use strict;
use warnings;
use Errno qw(EINTR EAGAIN);
use JSON;
use URI::Escape;
use IO::Select;
use IO::Socket::SSL;
use MIME::Base64;
use Digest::SHA;
use HTTP::Response;

use PVE::Tools;
use PVE::JSONSchema qw(get_standard_option);
use PVE::CLIHandler;
use PVE::PTY;

use base qw(PVE::CLIHandler);
use PVE::APIClient::Config;

my $CRLF = "\x0D\x0A";
my $max_payload_size = 128*1024;

my $build_web_socket_request = sub {
    my ($host, $path, $ticket, $termproxy) = @_;

    my $key = '';
    $key .= chr(int(rand(256))) for 1 .. 16;
    my $enckey = MIME::Base64::encode_base64($key, '');

    my $encticket = uri_escape($ticket);
    my $cookie = "PVEAuthCookie=$encticket; path=/; secure;";

    $path .= "?port=$termproxy->{port}" .
	"&vncticket=" . uri_escape($termproxy->{ticket});

    my $request = "GET $path HTTP/1.1$CRLF"
	. "Upgrade: WebSocket$CRLF"
	. "Connection: Upgrade$CRLF"
	. "Host: $host$CRLF"
	. "Sec-WebSocket-Key: $enckey$CRLF"
	. "Sec-WebSocket-Version: 13$CRLF"
	. "Sec-WebSocket-Protocol: binary$CRLF"
	. "Cookie: $cookie$CRLF"
	. "$CRLF";

    return ($request, $enckey);
};

my $create_websockt_frame = sub {
    my ($payload) = @_;

    my $string = "\x82"; # binary frame
    my $payload_len = length($payload);
    if ($payload_len <= 125) {
	$string .= pack 'C', $payload_len | 128;
    } elsif ($payload_len <= 0xffff) {
	$string .= pack 'C', 126 | 128;
	$string .= pack 'n', $payload_len;
    } else {
	$string .= pack 'C', 127 | 128;
	$string .= pack 'Q>', $payload_len;
    }

    $string .= pack 'N', 0; # we simply use 0 as mask
    $string .= $payload;

    return $string;
};

my $parse_web_socket_frame = sub  {
    my ($wsbuf_ref) = @_;

    my $payload;
    my $req_close = 0;

    while (my $len = length($$wsbuf_ref)) {
	last if $len < 2;

	my $hdr = unpack('C', substr($$wsbuf_ref, 0, 1));
	my $opcode = $hdr & 0b00001111;
	my $fin = $hdr & 0b10000000;

	die "received fragmented websocket frame\n" if !$fin;

	my $rsv = $hdr & 0b01110000;
	die "received websocket frame with RSV flags\n" if $rsv;

	my $payload_len = unpack 'C', substr($$wsbuf_ref, 1, 1);

	my $masked = $payload_len & 0b10000000;
	die "received masked websocket frame from server\n" if $masked;

	my $offset = 2;
	$payload_len = $payload_len & 0b01111111;
	if ($payload_len == 126) {
	    last if $len < 4;
	    $payload_len = unpack('n', substr($$wsbuf_ref, $offset, 2));
	    $offset += 2;
	} elsif ($payload_len == 127) {
	    last if $len < 10;
	    $payload_len = unpack('Q>', substr($$wsbuf_ref, $offset, 8));
	    $offset += 8;
	}

	die "received too large websocket frame (len = $payload_len)\n"
	    if ($payload_len > $max_payload_size) || ($payload_len < 0);

	last if $len < ($offset + $payload_len);

	my $data = substr($$wsbuf_ref, 0, $offset + $payload_len, ''); # now consume data

	my $frame_data = substr($data, $offset, $payload_len);

	$payload = '' if !defined($payload);
	$payload .= $frame_data;

	if ($opcode == 1 || $opcode == 2) {
	    # continue
	} elsif ($opcode == 8) {
	    my $statuscode = unpack ("n", $frame_data);
	    $req_close = 1;
	} else {
	    die "received unhandled websocket opcode $opcode\n";
	}
    }

    return ($payload, $req_close);
};

my $full_write = sub {
    my ($fh, $data) = @_;

    my $len = length($data);
    my $todo = $len;
    my $offset = 0;
    while(1) {
	my $nr = syswrite($fh, $data, $todo, $offset);
	if (!defined($nr)) {
	    next if $! == EINTR || $! == EAGAIN;
	    die "console write error - $!\n"
	}
	$offset += $nr;
	$todo -= $nr;
	last if $todo <= 0;
    }

    return $len;
};

# Takes an escape character with an optional '^' prefix and returns an escape
# character code.
my $escapekey_to_char = sub {
    my ($def) = @_;
    if ($def =~ /^\^?([a-zA-Z])$/) {
	return 1 + ord(lc($1)) - ord('a');
    }
    die "bad escape key definition: $def\n";
};

__PACKAGE__->register_method ({
    name => 'enter',
    path => 'enter',
    method => 'POST',
    description => "Enter container console.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    remote => get_standard_option('pveclient-remote-name'),
	    vmid => {
		description => "The container ID",
		type => 'string',
	    },
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	my $config = PVE::APIClient::Config->load();
	my $conn = PVE::APIClient::Config->remote_conn($config, $param->{remote});

	# FIXME: This should come from $config
	my $escape_char = $escapekey_to_char->('a');

	# Get the real node from the resources endpoint
	my $resource_list = $conn->get("api2/json/cluster/resources", { type => 'vm'});
	my ($resource) = grep { $_->{type} eq "lxc" && $_->{vmid} eq $param->{vmid}} @$resource_list;

	die "container '$param->{vmid}' does not exist\n"
	    if !(defined($resource) && defined($resource->{node}));

	my $node = $resource->{node};

	my $api_path = "api2/json/nodes/$node/lxc/$param->{vmid}";

	my $termproxy = $conn->post("${api_path}/termproxy", {});

	my $web_socket =  IO::Socket::SSL->new(
	    PeerHost => $conn->{host},
	    PeerPort => $conn->{port},
	    SSL_verify_mode => SSL_VERIFY_NONE, # fixme: ???
	    timeout => 30) ||
	    die "failed to connect: $!\n";

	# WebSocket Handshake

	my ($request, $wskey) = $build_web_socket_request->(
	    $conn->{host}, "/$api_path/vncwebsocket", $conn->{ticket}, $termproxy);

	$full_write->($web_socket, $request);

	my $wsbuf = '';

	my $wb_socket_read_available_bytes = sub {
	    my $nr = $web_socket->sysread($wsbuf, $max_payload_size, length($wsbuf));
	    if (!defined($nr) && !($! == EINTR || $! == EAGAIN)) {
		die "web socket read error - $!\n";
	    }
	    return $nr;
	};

	my $raw_response = '';

	while(1) {
	    my $nr = $wb_socket_read_available_bytes->();
	    if ($wsbuf =~ s/^(.*?)$CRLF$CRLF//s) {
		$raw_response = $1;
		last;
	    }
	    last if !$nr;
	};

	# Note: we keep any remaining data in $wsbuf

	my $response = HTTP::Response->parse($raw_response);

	# Note: Digest::SHA::sha1_base64 has wrong padding
	my $wsaccept = Digest::SHA::sha1_base64("${wskey}258EAFA5-E914-47DA-95CA-C5AB0DC85B11") . "=";

	die "got invalid websocket reponse: $raw_response\n"
	    if !(($response->code == 101) &&
		 (lc $response->header('connection') eq 'upgrade') &&
		 (lc $response->header('upgrade') eq 'websocket') &&
		 ($response->header('sec-websocket-protocol') eq 'binary') &&
		 ($response->header('sec-websocket-accept') eq $wsaccept));

	# send auth again...
	my $frame = $create_websockt_frame->($termproxy->{user} . ":" . $termproxy->{ticket} . "\n");
	$full_write->($web_socket, $frame);

	# Send resize command
	my ($columns, $rows) = PVE::PTY::tcgetsize(*STDIN);
	$frame = $create_websockt_frame->("1:$columns:$rows:");
	$full_write->($web_socket, $frame);

	# Set STDIN to "raw -echo" mode
	my $old_termios = PVE::PTY::tcgetattr(*STDIN);
	my $raw_termios = {%$old_termios};

	my $read_select = IO::Select->new;
	my $write_select = IO::Select->new;

	my $output_buffer = ''; # write buffer for STDOUT
	my $websock_buffer = ''; # write buffer for $web_socket

	eval {
	    $SIG{TERM} = $SIG{INT} = $SIG{KILL} = sub { die "received interrupt\n"; };

	    PVE::PTY::cfmakeraw($raw_termios);
	    PVE::PTY::tcsetattr(*STDIN, $raw_termios);

	    # And set it to non-blocking so we can every char with IO::Select.
	    STDIN->blocking(0);
	    STDOUT->blocking(0);
	    $web_socket->blocking(0);
	    $read_select->add($web_socket);
	    my $input_fh = \*STDIN;
	    $read_select->add($input_fh);

	    my $output_fh = \*STDOUT;

	    my $in_escape_sequence;

	    my $winch_received = 0;
	    $SIG{WINCH} = sub { $winch_received = 1; };

	    my $check_terminal_size = sub {
		my ($ncols, $nrows) = PVE::PTY::tcgetsize(*STDIN);
		if ($ncols != $columns or $nrows != $rows) {
		    $columns = $ncols;
		    $rows = $nrows;
		    $websock_buffer .= $create_websockt_frame->("1:$columns:$rows:");
		    $write_select->add($web_socket);
		}
		$winch_received = 0;
	    };

	    my $max_buffer_len = 256*1024;

	    my $drain_buffer = sub {
		my ($fh, $buffer_ref) = @_;

		my $len = length($$buffer_ref);
		my $nr = syswrite($fh, $$buffer_ref);
		if (!defined($nr)) {
		    return if $! == EINTR || $! == EAGAIN;
		    die "drain buffer - write error - $!\n";
		}
		return $nr if !$nr;
		substr($$buffer_ref, 0, $nr, '');
		$len = length($$buffer_ref);
		$write_select->remove($fh) if !$len;
	    };

	    while (1) {
		while(my ($readable, $writable) = IO::Select->select($read_select, $write_select, undef, 3)) {
		    $check_terminal_size->() if $winch_received;

		    foreach my $fh (@$writable) {
			if ($fh == $output_fh) {
			    $drain_buffer->($output_fh, \$output_buffer);
			    $read_select->add($web_socket) if length($output_buffer) <= $max_buffer_len;
			} elsif ($fh == $web_socket) {
			    $drain_buffer->($web_socket, \$websock_buffer);
			}
		    }

		    foreach my $fh (@$readable) {

			if ($fh == $web_socket) {
			    # Read from WebSocket

			    my $nr = $wb_socket_read_available_bytes->();
			    if (!defined($nr)) {
				# wait
			    } elsif ($nr == 0) {
				return; # EOF
			    } else {
				my ($payload, $req_close) = $parse_web_socket_frame->(\$wsbuf);
				if (defined($payload) && length($payload)) {
				    $output_buffer .= $payload;
				    $write_select->add($output_fh);
				    if (length($output_buffer) > $max_buffer_len) {
					$read_select->remove($web_socket);
				    }
				}
				return if $req_close;
			    }

			} elsif ($fh == $input_fh) {
			    # Read from STDIN

			    my $nr = sysread($input_fh, my $buff, 4096);
			    return if !$nr; # EOF or error

			    my $char = ord($buff);

			    # Handle escape sequences:
			    if ($in_escape_sequence) {
				$in_escape_sequence = 0;
				if ($char == 0x71) {
				    # (escape, 'q')
				    return;
				} elsif ($char == $escape_char) {
				    # (escape, escape)
				    # Pass this one through as a single escapekey
				} else {
				    # Unknown escape sequence
				    # We could generate a bell or something...
				    # but for now just skip it
				    next;
				}
			    } elsif ($char == $escape_char) {
				$in_escape_sequence = 1;
				next;
			    }

			    # Pass the key through:
			    $websock_buffer .= $create_websockt_frame->("0:" . $nr . ":" . $buff);
			    $write_select->add($web_socket);
			}
		    }
		}
		$check_terminal_size->() if $winch_received;

		# got timeout
		$websock_buffer .= $create_websockt_frame->("2"); # ping server to keep connection alive
		$write_select->add($web_socket);
	    }
	};
	my $err = $@;

	eval {  # cleanup

	    # switch back to blocking mode (else later shell commands will fail).
	    STDIN->blocking(1);

	    if ($web_socket->connected) {
		# close connection
		$websock_buffer .= "\x88" . pack('N', 0) . pack('n', 0); # Opcode, mask, statuscode
		$full_write->($web_socket, $websock_buffer);
		$websock_buffer = '';
		close($web_socket);
	    }

	    # Reset the terminal parameters.
	    $output_buffer .= "\e[24H\r\n";
	    $full_write->(\*STDOUT, $output_buffer);
	    $output_buffer = '';

	    PVE::PTY::tcsetattr(*STDIN, $old_termios);
	};
	warn $@ if $@; # show cleanup errors

	print STDERR "\nERROR: $err" if $err;

	return undef;
    }});

our $cmddef = {
    enter => [ __PACKAGE__, 'enter', ['remote', 'vmid']],
};

1;
