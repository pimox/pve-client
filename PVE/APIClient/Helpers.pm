package PVE::APIClient::Helpers;

use strict;
use warnings;

use Storable;
use JSON;
use File::Path qw(make_path);

use PVE::APIClient::JSONSchema;
use PVE::APIClient::Exception qw(raise);
use Encode::Locale;
use Encode;
use HTTP::Status qw(:constants);

my $pve_api_definition;

my $pve_api_definition_fn = "/usr/share/pve-client/pve-api-definition.dat";

my $method_map = {
    create => 'POST',
    set => 'PUT',
    get => 'GET',
    delete => 'DELETE',
};

my $default_output_format = 'text';
my $client_output_format =  $default_output_format;

sub set_output_format {
    my ($format) = @_;

    if (!defined($format)) {
	$client_output_format =  $default_output_format;
    } else {
	$client_output_format =  $format;
    }
}

sub get_output_format {
    return $client_output_format;
}

sub print_result {
    my ($data, $result_schema) = @_;

    my $format = get_output_format();

    return if $result_schema->{type} eq 'null';

    # TODO: implement different output formats ($format)

    if ($format eq 'json') {
	print to_json($data, {utf8 => 1, allow_nonref => 1, canonical => 1, pretty => 1 });
    } elsif ($format eq 'text') {
	my $type = $result_schema->{type};
	if ($type eq 'object') {
	    die "implement me";
	} elsif ($type eq 'array') {
	    my $item_type = $result_schema->{items}->{type};
	    if ($item_type eq 'object') {
		die "implement me";
	    } elsif ($item_type eq 'array') {
		die "implement me";
	    } else {
		foreach my $el (@$data) {
		    print "$el\n"
		}
	    }
	} else {
	    print "$data\n";
	}
    } else {
	die "internal error: unknown output format"; # should not happen
    }
}


my $__real_remove_formats; $__real_remove_formats = sub {
    my ($properties) = @_;

    foreach my $pname (keys %$properties) {
	if (my $d = $properties->{$pname}) {
	    if (defined(my $format = $d->{format})) {
		if (ref($format)) {
		    $__real_remove_formats->($format);
		} elsif (!PVE::APIClient::JSONSchema::get_format($format)) {
		    # simply remove unknown format definitions
		    delete $d->{format};
		}
	    }
	}
    }
};

my $remove_unknown_formats; $remove_unknown_formats = sub {
    my ($tree) = @_;

    my $class = ref($tree);
    return if !$class;

    if ($class eq 'ARRAY') {
       foreach my $el (@$tree) {
	   $remove_unknown_formats->($el);
       }
    } elsif ($class eq 'HASH') {
	if (my $info = $tree->{info}) {
	    for my $method (qw(GET PUT PUSH DELETE)) {
		next if !$info->{$method};
		my $properties = $info->{$method}->{parameters}->{properties};
		$__real_remove_formats->($properties) if $properties;
	    }
	}
	if ($tree->{children}) {
	    $remove_unknown_formats->($tree->{children});
	}
    }
    return;
};

sub get_api_definition {

    if (!defined($pve_api_definition)) {
	open(my $fh, '<',  $pve_api_definition_fn) ||
	    die "unable to open '$pve_api_definition_fn' - $!\n";
	$pve_api_definition = Storable::fd_retrieve($fh);

	$remove_unknown_formats->($pve_api_definition);
    }

    return $pve_api_definition;
}

my $map_path_to_info = sub {
    my ($child_list, $stack, $uri_param) = @_;

    while (defined(my $comp = shift @$stack)) {
	foreach my $child (@$child_list) {
	    my $text = $child->{text};

	    if ($text eq $comp) {
		# found
	    } elsif ($text =~ m/^\{(\S+)\}$/) {
		# found
		$uri_param->{$1} = $comp;
	    } else {
		next; # text next child
	    }
	    if ($child->{leaf} || !scalar(@$stack)) {
		return $child;
	    } else {
		$child_list = $child->{children};
		last; # test next path component
	    }
	}
    }
    return undef;
};

sub find_method_info {
    my ($path, $method, $uri_param, $noerr) = @_;

    $uri_param //= {};

    my $stack = [ grep { length($_) > 0 }  split('\/+' , $path)]; # skip empty fragments

    my $child = $map_path_to_info->(get_api_definition(), $stack, $uri_param);

    if (!($child && $child->{info} && $child->{info}->{$method})) {
	return undef if $noerr;
	die "unable to find API method '$method' for path '$path'\n";
    }

    return $child->{info}->{$method};
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
	my $stack = [ grep { length($_) > 0 }  split('\/+' , $dir)]; # skip empty fragments
	$info = $map_path_to_info->($pve_api_definition, $stack, {});
    }

    my $res = [];
    if ($info) {
	my $prefix = length($dir) ? "/$dir/" : '/';
	if (my $children = $info->{children}) {
	    foreach my $c (@$children) {
		my $ctext = $c->{text};
		if ($ctext =~ m/^\{(\S+)\}$/) {
		    push @$res, "$prefix$ctext";
		    push @$res, "$prefix$ctext/";
		    if (length($rest)) {
			push @$res, "$prefix$rest";
			push @$res, "$prefix$rest/";
		    }
		} elsif ($ctext =~ m/^\Q$rest/) {
		    push @$res, "$prefix$ctext";
		    push @$res, "$prefix$ctext/" if $c->{children};
		}
	    }
	}
    }

    return $res;
}

# test for command lines with api calls (or similar bash completion calls):
# example1: pveclient api get remote1 /cluster
sub extract_path_info {
    my ($uri_param) = @_;

    my $info;

    my $test_path_properties = sub {
	my ($args) = @_;

	return if scalar(@$args) < 5;
	return if $args->[1] ne 'api';

	my $path = $args->[4];
	if (my $method = $method_map->{$args->[2]}) {
	    $info = find_method_info($path, $method, $uri_param, 1);
	}
    };

    if (defined(my $cmd = $ARGV[0])) {
	if ($cmd eq 'api') {
	    $test_path_properties->([$0, @ARGV]);
	} elsif ($cmd eq 'bashcomplete') {
	    my $cmdline = substr($ENV{COMP_LINE}, 0, $ENV{COMP_POINT});
	    my $args = PVE::APIClient::Tools::split_args($cmdline);
	    $test_path_properties->($args);
	}
    }

    return $info;
}

sub get_vmid_resource {
    my ($conn, $vmid) = @_;

    my $resources = $conn->get('api2/json/cluster/resources', {type => 'vm'});

    my $resource;
    for my $tmp (@$resources) {
	if ($tmp->{vmid} eq $vmid) {
	    $resource = $tmp;
	    last;
	}
    }

    if (!defined($resource)) {
	die "\"$vmid\" not found";
    }

    return $resource;
}

sub poll_task {
    my ($conn, $node, $upid) = @_;

    my $path = "api2/json/nodes/$node/tasks/$upid/status";

    my $task_status;
    while(1) {
	$task_status = $conn->get($path, {});

	if ($task_status->{status} eq "stopped") {
	    last;
	}

	sleep(10);
    }

    return $task_status->{exitstatus};
}

sub configuration_directory {

    my $home = $ENV{HOME} // '';
    my $xdg = $ENV{XDG_CONFIG_HOME} // '';

    my $subdir = "pveclient";

    return "$xdg/$subdir" if length($xdg);

    return "$home/.config/$subdir" if length($home);

    die "neither XDG_CONFIG_HOME nor HOME environment variable set\n";
}

my $ticket_cache_filename = "/.tickets";

sub ticket_cache_lookup {
    my ($remote) = @_;

    my $dir = configuration_directory();
    my $filename = "$dir/$ticket_cache_filename";

    my $data = {};
    eval { $data = from_json(PVE::APIClient::Tools::file_get_contents($filename)); };
    # ignore errors

    my $ticket = $data->{$remote};
    return undef if !defined($ticket);

    my $min_age = - 60;
    my $max_age = 3600*2 - 60;

    if ($ticket =~ m/:([a-fA-F0-9]{8})::/) {
	my $ttime = hex($1);
	my $ctime = time();
	my $age = $ctime - $ttime;

	return $ticket if ($age > $min_age) && ($age < $max_age);
    }

    return undef;
}

sub ticket_cache_update {
    my ($remote, $ticket) = @_;

    my $dir = configuration_directory();
    my $filename = "$dir/$ticket_cache_filename";

    my $code = sub {
	make_path($dir);
	my $data = {};
	if (-f $filename) {
	    my $raw = PVE::APIClient::Tools::file_get_contents($filename);
	    eval { $data = from_json($raw); };
	    # ignore errors
	}
	$data->{$remote} = $ticket;

	PVE::APIClient::Tools::file_set_contents($filename, to_json($data), 0600);
    };

    PVE::APIClient::Tools::lock_file($filename, undef, $code);
    die $@ if $@;
}


1;
