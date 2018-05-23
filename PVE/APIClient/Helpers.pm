package PVE::APIClient::Helpers;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use PVE::APIClient::Exception qw(raise);
use Encode::Locale;
use Encode;
use HTTP::Status qw(:constants);

my $pve_api_definition;
my $pve_api_path_hash;

my $pve_api_definition_fn = "/usr/share/pve-client/pve-api-definition.js";

my $build_pve_api_path_hash;
$build_pve_api_path_hash = sub {
    my ($tree) = @_;

    my $class = ref($tree);
    return $tree if !$class;

    if ($class eq 'ARRAY') {
	foreach my $el (@$tree) {
	    $build_pve_api_path_hash->($el);
	}
    } elsif ($class eq 'HASH') {
	if (defined($tree->{leaf}) && defined(my $path = $tree->{path})) {
	    $pve_api_path_hash->{$path} = $tree;
	}
	foreach my $k (keys %$tree) {
	    $build_pve_api_path_hash->($tree->{$k});
	}
    }
};

sub get_api_definition {

    if (!defined($pve_api_definition)) {
	local $/;
	open(my $fh, '<',  $pve_api_definition_fn) ||
	    die "unable to open '$pve_api_definition_fn' - $!\n";
	my $json_text = <$fh>;
	$pve_api_definition = decode_json($json_text);

	$build_pve_api_path_hash->($pve_api_definition);
    }


    return $pve_api_definition;
}

sub lookup_api_method {
    my ($path, $method) = @_;

    get_api_definition(); # make sure API data is loaded

    my $info = $pve_api_path_hash->{$path} ||
	die "unable to find API info for path '$path'\n";

    my $data = $info->{info}->{$method} ||
	die "unable to find API method '$method' for path '$path'\n";

    return $data;
}

1;
