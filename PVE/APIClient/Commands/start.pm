package PVE::APIClient::Commands::start;

use strict;
use warnings;

use PVE::APIClient::Helpers;
use PVE::JSONSchema qw(get_standard_option);

use PVE::CLIHandler;

use base qw(PVE::CLIHandler);

__PACKAGE__->register_method ({
    name => 'start',
    path => 'start',
    method => 'POST',
    description => "Start a Qemu VM/LinuX Container.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    remote => get_standard_option('pveclient-remote-name'),
	    vmid => get_standard_option('pve-vmid'),
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	my $config = PVE::APIClient::Config->load();
	my $conn = PVE::APIClient::Config->remote_conn($config, $param->{remote});

	my $resource = PVE::APIClient::Helpers::get_vmid_resource($conn, $param->{vmid});

	my $upid = $conn->post("api2/json/nodes/$resource->{node}/$resource->{type}/$resource->{vmid}/status/start", {});

	print PVE::APIClient::Helpers::poll_task($conn, $resource->{node}, $upid) . "\n";

	return undef;
    }});

our $cmddef = [ __PACKAGE__, 'start', ['remote', 'vmid']];

1;
