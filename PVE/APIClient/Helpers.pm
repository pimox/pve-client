package PVE::APIClient::Helpers;

use strict;
use warnings;

use Storable;
use JSON;
use PVE::APIClient::Exception qw(raise);
use Encode::Locale;
use Encode;
use HTTP::Status qw(:constants);

my $pve_api_definition;
my $pve_api_path_hash;

my $pve_api_definition_fn = "/usr/share/pve-client/pve-api-definition.dat";

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
	open(my $fh, '<',  $pve_api_definition_fn) ||
	    die "unable to open '$pve_api_definition_fn' - $!\n";
	$pve_api_definition = Storable::fd_retrieve($fh);
	$build_pve_api_path_hash->($pve_api_definition);
    }

    return $pve_api_definition;
}

sub lookup_api_method {
    my ($path, $method, $noerr) = @_;

    get_api_definition(); # make sure API data is loaded

    my $info = $pve_api_path_hash->{$path};

    if (!$info) {
	return undef if $noerr;
	die "unable to find API info for path '$path'\n";
    }

    my $data = $info->{info}->{$method};

    if (!$data) {
	return undef if $noerr;
	die "unable to find API method '$method' for path '$path'\n";
    }

    return $data;
}

sub complete_api_call_options {
    my ($cmd, $prop, $prev, $cur, $args) = @_;

    my $print_result = sub {
	foreach my $p (@_) {
	    print "$p\n" if $p =~ m/^$cur/;
	}
    };

    my $print_parameter_completion = sub {
	my ($pname) = @_;
	my $d = $prop->{$pname};
	if ($d->{completion}) {
	    my $vt = ref($d->{completion});
	    if ($vt eq 'CODE') {
		my $res = $d->{completion}->($cmd, $pname, $cur, $args);
		&$print_result(@$res);
	    }
	} elsif ($d->{type} eq 'boolean') {
	    &$print_result('0', '1');
	} elsif ($d->{enum}) {
	    &$print_result(@{$d->{enum}});
	}
    };

    my @option_list = ();
    foreach my $key (keys %$prop) {
	push @option_list, "--$key";
    }

    if ($cur =~ m/^-/) {
	&$print_result(@option_list);
	return;
    }

    if ($prev =~ m/^--?(.+)$/ && $prop->{$1}) {
	my $pname = $1;
	&$print_parameter_completion($pname);
	return;
    }

    &$print_result(@option_list);
}

sub complete_api_path {
    my ($text) = @_;

    get_api_definition(); # make sure API data is loaded

    $text =~ s!^/!!;

    my ($dir, $rest) = $text =~ m|^(?:(.*)/)?(?:([^/]*))?$|;

    my $info;
    if (!defined($dir)) {
	$dir = '';
	$info = { children => $pve_api_definition };
    } else {
	$info = $pve_api_path_hash->{"/$dir"};
    }

    if ($info) {
	if (my $children = $info->{children}) {
	    foreach my $c (@$children) {
		if ($c->{path} =~ m!\Q$dir/$rest!) {
		    print "$c->{path}\n";
		    print "$c->{path}/\n"if $c->{children};
		}
	    }
	}
    }
}

1;
