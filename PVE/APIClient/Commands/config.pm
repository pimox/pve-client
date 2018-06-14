package PVE::APIClient::Commands::config;

use strict;
use warnings;
use Data::Dumper;

use PVE::APIClient::JSONSchema qw(get_standard_option);
use PVE::APIClient::Tools qw(extract_param);
use PVE::APIClient::Config;

use PVE::APIClient::CLIHandler;

use base qw(PVE::APIClient::CLIHandler);

__PACKAGE__->register_method ({
    name => 'list',
    path => 'list',
    method => 'GET',
    description => "Dump default configuration.",
    parameters => {
	additionalProperties => 0,
    },
    returns => { type => 'null' },
    code => sub {

	my $config = PVE::APIClient::Config->load();
	
	my $defaults = PVE::APIClient::Config->get_defaults($config);

	
	print Dumper($config);
	
	return undef;
    }});

__PACKAGE__->register_method ({
    name => 'set',
    path => 'set',
    method => 'PUT',
    description => "Update a remote configuration.",
    parameters => PVE::APIClient::DefaultsConfig->updateSchema(1),
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	# fixme: lock config file

	my $digest = extract_param($param, 'digest');
	my $delete = extract_param($param, 'delete');

	my $config = PVE::APIClient::Config->load();
	my $defaults = PVE::APIClient::Config->get_defaults($config);
	
	my $plugin = PVE::APIClient::Config->lookup('defaults');
	my $opts = $plugin->check_config('defaults', $param, 0, 1);

	foreach my $k (%$opts) {
	    $defaults->{$k} = $opts->{$k};
	}

	if ($delete) {
	    my $options = $plugin->private()->{options}->{'defaults'};
	    foreach my $k (PVE::APIClient::Tools::split_list($delete)) {
		my $d = $options->{$k} ||
		    die "no such option '$k'\n";
		die "unable to delete required option '$k'\n"
		    if !$d->{optional};
		die "unable to delete fixed option '$k'\n"
		    if $d->{fixed};
		delete $defaults->{$k};
	    }
	}

	PVE::APIClient::Config->save($config);

	return undef;
    }});


our $cmddef = {
    set => [ __PACKAGE__, 'set',],
    list => [__PACKAGE__, 'list'],
};

1;
