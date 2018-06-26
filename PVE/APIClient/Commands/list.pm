package PVE::APIClient::Commands::list;

use strict;
use warnings;
use JSON;

use PVE::APIClient::JSONSchema qw(get_standard_option);

use PVE::APIClient::Helpers;
use PVE::APIClient::Config;
use PVE::APIClient::CLIHandler;

use base qw(PVE::APIClient::CLIHandler);

# define as array to keep ordering
my $list_returns_properties = [
    'vmid' => get_standard_option('pve-vmid'),
    'node' => get_standard_option('pve-node'),
    'type' => { type => 'string' },
    'status' =>  { type => 'string' },
    'name' => { type => 'string', optional => 1 },
    ];

__PACKAGE__->register_method ({
    name => 'list',
    path => 'list',
    method => 'GET',
    description => "List containers.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    remote => get_standard_option('pveclient-remote-name'),
	    'format' => get_standard_option('pveclient-output-format'),
	},
    },
    returns => {
	type => 'array',
	items => {
	    type => 'object',
	    properties => { @$list_returns_properties },
	},
    },
    code => sub {
	my ($param) = @_;

	my $format = PVE::APIClient::Tools::extract_param($param, 'format');
	PVE::APIClient::Helpers::set_output_format($format);

	my $config = PVE::APIClient::Config->load();
	my $conn = PVE::APIClient::Config->remote_conn($config, $param->{remote});

	return $conn->get('api2/json/cluster/resources', { type => 'vm' });
    }});


our $cmddef = [ __PACKAGE__, 'list', ['remote'], {}, sub {
    PVE::APIClient::Helpers::print_ordered_result($list_returns_properties, @_);
}];

1;
