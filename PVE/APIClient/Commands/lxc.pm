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

use base qw(PVE::CLIHandler);
use PVE::APIClient::Config;

my $CRLF = "\x0D\x0A";
my $max_payload_size = 65536;

my $build_web_socket_request = sub {
    my ($path, $ticket, $termproxy) = @_;

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

	my $conn = PVE::APIClient::Config::get_remote_connection($param->{remote});

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
	    "/$api_path/vncwebsocket", $conn->{ticket}, $termproxy);

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
		 ($response->header('connection') eq 'upgrade') &&
		 ($response->header('upgrade') eq 'websocket') &&
		 ($response->header('sec-websocket-protocol') eq 'binary') &&
		 ($response->header('sec-websocket-accept') eq $wsaccept));

	# send auth again...
	my $frame = $create_websockt_frame->($termproxy->{user} . ":" . $termproxy->{ticket} . "\n");
	$web_socket->syswrite($frame);

	my $select = IO::Select->new;

	$web_socket->blocking(0);
	$select->add($web_socket);

	while(my @ready = $select->can_read) {
	    foreach my $fh (@ready) {
		if ($fh == $web_socket) {
		    my $nr = $wb_socket_read_available_bytes->();
		    my ($payload, $req_close) = $parse_web_socket_frame->(\$wsbuf);
		    print "GOT: $payload\n" if defined($payload);
		    last if $req_close;
		    last if !$nr; # eos
		} else {
		    die "internal error - unknown handle";
		}
	    }
	}

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
