package PVE::APIClient::Config;

use strict;
use warnings;
use JSON;
use File::HomeDir;

use PVE::Tools;

sub load_config {

    my $filename = home() . '/.pveclient';
    my $conf_str = PVE::Tools::file_get_contents($filename);

    my $filemode = (stat($filename))[2] & 07777;
    if ($filemode != 0600) {
	die sprintf "wrong permissions on '$filename' %04o (expected 0600)\n", $filemode;
    }

    return decode_json($conf_str);
};

1;
