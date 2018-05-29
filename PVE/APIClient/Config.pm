package PVE::APIClient::Config;

use strict;
use warnings;
use JSON;
use File::HomeDir;

use PVE::Tools;
use PVE::APIClient::LWP;

sub load_config {

    my $filename = home() . '/.pveclient';
    my $conf_str = PVE::Tools::file_get_contents($filename);

    my $filemode = (stat($filename))[2] & 07777;
    if ($filemode != 0600) {
	die sprintf "wrong permissions on '$filename' %04o (expected 0600)\n", $filemode;
    }

    return decode_json($conf_str);
}

sub load_remote_config {
    my ($remote) = @_;

    my $conf = load_config();

    my $remote_conf = $conf->{"remote_$remote"} ||
	die "no such remote '$remote'\n";

    foreach my $opt (qw(hostname username password fingerprint)) {
	die "missing option '$opt' (remote '$remote')" if !defined($remote_conf->{$opt});
    }

    return $remote_conf;
}

sub get_remote_connection {
    my ($remote) = @_;

    my $conf = load_remote_config($remote);

    return PVE::APIClient::LWP->new(
	username => $conf->{username},
	password => $conf->{password},
	host => $conf->{hostname},
	cached_fingerprints => {
	    $conf->{fingerprint} => 1
	});
}

1;
