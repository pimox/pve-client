package PVE::APIClient::Commands::lxc;

use strict;
use warnings;
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
my $max_payload_size = 65536;

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

    my $wsbuf = $$wsbuf_ref;

    my $payload;
    my $req_close = 0;

    while (my $len = length($wsbuf)) {
	last if $len < 2;

	my $hdr = unpack('C', substr($wsbuf, 0, 1));
	my $opcode = $hdr & 0b00001111;
	my $fin = $hdr & 0b10000000;

	die "received fragmented websocket frame\n" if !$fin;

	my $rsv = $hdr & 0b01110000;
	die "received websocket frame with RSV flags\n" if $rsv;

	my $payload_len = unpack 'C', substr($wsbuf, 1, 1);

	my $masked = $payload_len & 0b10000000;
	die "received masked websocket frame from server\n" if $masked;

	my $offset = 2;
	$payload_len = $payload_len & 0b01111111;
	if ($payload_len == 126) {
	    last if $len < 4;
	    $payload_len = unpack('n', substr($wsbuf, $offset, 2));
	    $offset += 2;
	} elsif ($payload_len == 127) {
	    last if $len < 10;
	    $payload_len = unpack('Q>', substr($wsbuf, $offset, 8));
	    $offset += 8;
	}

	die "received too large websocket frame (len = $payload_len)\n"
	    if ($payload_len > $max_payload_size) || ($payload_len < 0);

	last if $len < ($offset + $payload_len);

	my $data = substr($wsbuf, 0, $offset + $payload_len, ''); # now consume data

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

my $client_exit = sub {
    my ($select, $web_socket, $old_termios) = @_;

    foreach my $fh ($select->handles) {
	$select->remove($fh);

	if ($fh == $web_socket) {
	    if ($fh->connected) {

		# close connection
		# Opcode, mask, statuscode
		my $msg = "\x88" . pack('N', 0) . pack('n', 0);
		$fh->syswrite($msg);
		close($fh);
	    }
	}

    }

    #
    # Reset the terminal parameters.
    #
    print "\e[24H\r\n";
    PVE::PTY::tcsetattr(*STDIN, $old_termios);
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

	$web_socket->syswrite($request);

	my $wsbuf = '';

	my $wb_socket_read_available_bytes = sub {
	    my $nr = $web_socket->sysread($wsbuf, $max_payload_size, length($wsbuf));
	    die "web socket read error - $!\n" if $nr < 0;
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
	$web_socket->syswrite($frame);

	# Send resize command
	my ($columns, $rows) = PVE::PTY::tcgetsize(*STDIN);
	$frame = $create_websockt_frame->("1:$columns:$rows:");
	$web_socket->syswrite($frame);

	# Set STDIN to "raw -echo" mode
	my $old_termios = PVE::PTY::tcgetattr(*STDIN);
	my $raw_termios = {%$old_termios};
	PVE::PTY::cfmakeraw($raw_termios);
	PVE::PTY::tcsetattr(*STDIN, $raw_termios);

	# And set it to non-blocking so we can every char with IO::Select.
	STDIN->blocking(0);

	my $select = IO::Select->new;

	$web_socket->blocking(0);
	$select->add($web_socket);
	$select->add(fileno(STDIN));

	my @messages;
	my $ctrl_a_pressed_before = 0;
	my $next_ping = time() + 3;

	eval {
	    while (1) {
		# Ping server every 3 seconds.
		my $now = time();
		if ($now >= $next_ping) {
		    push(@messages, $create_websockt_frame->("2"));
		    $next_ping = $now + 3;
		}

		# Write
		foreach my $fh ($select->can_write(0.5)) {
		    if ($fh == $web_socket and my $msg = shift @messages) {
			$fh->syswrite($msg, length($msg));
		    }
		}

		# Read
		foreach my $fh ($select->can_read(0.5)) {

		    # From Web Socket
		    if ($fh == $web_socket) {
			# Read from WebSocket
			my $nr = $wb_socket_read_available_bytes->();
			my ($payload, $req_close) = $parse_web_socket_frame->(\$wsbuf);

			if ($payload ne "OK") {
			    syswrite(\*STDOUT, $payload, length($payload));
			}
		    }

		    # From STDIN
		    elsif ($fh == fileno(STDIN)) {

			# Read from STDIN
			my $nr = read(\*STDIN, my $buff, 4096);
			if (!$nr) {
			    next;
			}

			my $char = ord($buff);

			if ($ctrl_a_pressed_before == 1 && $char == hex("0x71")) {
			    $client_exit->($select, $web_socket, $old_termios);
			    return;
			}

			if ($char == hex("0x01")) {
			    if ($ctrl_a_pressed_before == 0) {
				$ctrl_a_pressed_before = 1;
			    }
			}
			else {
			    $ctrl_a_pressed_before = 0;
			}

			push(@messages, $create_websockt_frame->("0:" . $nr . ":" . $buff));
		    }
		}
	    }
	};
	print "ERROR: " . $@ . ".\n" if $@;

	$client_exit->($select, $web_socket, $old_termios);

	return undef
    }});

__PACKAGE__->register_method ({
    name => 'list',
    path => 'list',
    method => 'GET',
    description => "List containers.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    remote => get_standard_option('pveclient-remote-name'),
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	die "implement me";

    }});


our $cmddef = {
    enter => [ __PACKAGE__, 'enter', ['remote', 'vmid']],
    list => [ __PACKAGE__, 'list', ['remote']],
};

1;
