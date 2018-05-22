package PVE::APIClient::Helpers;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use PVE::APIClient::Exception qw(raise);
use Getopt::Long;
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

# Getopt wrapper - copied from PVE::JSONSchema::get_options
# a way to parse command line parameters, using a
# schema to configure Getopt::Long
sub get_options {
    my ($schema, $args, $arg_param, $fixed_param, $pwcallback, $param_mapping_hash) = @_;

    if (!$schema || !$schema->{properties}) {
	raise("too many arguments\n", code => HTTP_BAD_REQUEST)
	    if scalar(@$args) != 0;
	return {};
    }

    my $list_param;
    if ($arg_param && !ref($arg_param)) {
	my $pd = $schema->{properties}->{$arg_param};
	die "expected list format $pd->{format}"
	    if !($pd && $pd->{format} && $pd->{format} =~ m/-list/);
	$list_param = $arg_param;
    }

    my @interactive = ();
    my @getopt = ();
    foreach my $prop (keys %{$schema->{properties}}) {
	my $pd = $schema->{properties}->{$prop};
	next if $list_param && $prop eq $list_param;
	next if defined($fixed_param->{$prop});

	my $mapping = $param_mapping_hash->{$prop};
	if ($mapping && $mapping->{interactive}) {
	    # interactive parameters such as passwords: make the argument
	    # optional and call the mapping function afterwards.
	    push @getopt, "$prop:s";
	    push @interactive, [$prop, $mapping->{func}];
	} elsif ($prop eq 'password' && $pwcallback) {
	    # we do not accept plain password on input line, instead
	    # we turn this into a boolean option and ask for password below
	    # using $pwcallback() (for security reasons).
	    push @getopt, "$prop";
	} elsif ($pd->{type} eq 'boolean') {
	    push @getopt, "$prop:s";
	} else {
	    if ($pd->{format} && $pd->{format} =~ m/-a?list/) {
		push @getopt, "$prop=s@";
	    } else {
		push @getopt, "$prop=s";
	    }
	}
    }

    Getopt::Long::Configure('prefix_pattern=(--|-)');

    my $opts = {};
    raise("unable to parse option\n", code => HTTP_BAD_REQUEST)
	if !Getopt::Long::GetOptionsFromArray($args, $opts, @getopt);

    if (@$args) {
	if ($list_param) {
	    $opts->{$list_param} = $args;
	    $args = [];
	} elsif (ref($arg_param)) {
	    foreach my $arg_name (@$arg_param) {
		if ($opts->{'extra-args'}) {
		    raise("internal error: extra-args must be the last argument\n", code => HTTP_BAD_REQUEST);
		}
		if ($arg_name eq 'extra-args') {
		    $opts->{'extra-args'} = $args;
		    $args = [];
		    next;
		}
		raise("not enough arguments\n", code => HTTP_BAD_REQUEST) if !@$args;
		$opts->{$arg_name} = shift @$args;
	    }
	    raise("too many arguments\n", code => HTTP_BAD_REQUEST) if @$args;
	} else {
	    raise("too many arguments\n", code => HTTP_BAD_REQUEST)
		if scalar(@$args) != 0;
	}
    }

    if (my $pd = $schema->{properties}->{password}) {
	if ($pd->{type} ne 'boolean' && $pwcallback) {
	    if ($opts->{password} || !$pd->{optional}) {
		$opts->{password} = &$pwcallback();
	    }
	}
    }

    foreach my $entry (@interactive) {
	my ($opt, $func) = @$entry;
	my $pd = $schema->{properties}->{$opt};
	my $value = $opts->{$opt};
	if (defined($value) || !$pd->{optional}) {
	    $opts->{$opt} = $func->($value);
	}
    }

    # decode after Getopt as we are not sure how well it handles unicode
    foreach my $p (keys %$opts) {
	if (!ref($opts->{$p})) {
	    $opts->{$p} = decode('locale', $opts->{$p});
	} elsif (ref($opts->{$p}) eq 'ARRAY') {
	    my $tmp = [];
	    foreach my $v (@{$opts->{$p}}) {
		push @$tmp, decode('locale', $v);
	    }
	    $opts->{$p} = $tmp;
	} elsif (ref($opts->{$p}) eq 'SCALAR') {
	    $opts->{$p} = decode('locale', $$opts->{$p});
	} else {
	    raise("decoding options failed, unknown reference\n", code => HTTP_BAD_REQUEST);
	}
    }

    foreach my $p (keys %$opts) {
	if (my $pd = $schema->{properties}->{$p}) {
	    if ($pd->{type} eq 'boolean') {
		if ($opts->{$p} eq '') {
		    $opts->{$p} = 1;
		} elsif (defined(my $bool = parse_boolean($opts->{$p}))) {
		    $opts->{$p} = $bool;
		} else {
		    raise("unable to parse boolean option\n", code => HTTP_BAD_REQUEST);
		}
	    } elsif ($pd->{format}) {

		if ($pd->{format} =~ m/-list/) {
		    # allow --vmid 100 --vmid 101 and --vmid 100,101
		    # allow --dow mon --dow fri and --dow mon,fri
		    $opts->{$p} = join(",", @{$opts->{$p}}) if ref($opts->{$p}) eq 'ARRAY';
		} elsif ($pd->{format} =~ m/-alist/) {
		    # we encode array as \0 separated strings
		    # Note: CGI.pm also use this encoding
		    if (scalar(@{$opts->{$p}}) != 1) {
			$opts->{$p} = join("\0", @{$opts->{$p}});
		    } else {
			# st that split_list knows it is \0 terminated
			my $v = $opts->{$p}->[0];
			$opts->{$p} = "$v\0";
		    }
		}
	    }
	}
    }

    foreach my $p (keys %$fixed_param) {
	$opts->{$p} = $fixed_param->{$p};
    }

    return $opts;
}


1;
