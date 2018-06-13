package PVE::APIClient::Commands::GuestStatus;

use strict;
use warnings;

use PVE::APIClient::Helpers;
use PVE::APIClient::Config;

use PVE::JSONSchema qw(get_standard_option);

use PVE::CLIHandler;

use base qw(PVE::CLIHandler);

my $guest_status_command = sub {
    my ($remote, $vmid, $cmd, $param) = @_,

    my $config = PVE::APIClient::Config->load();
    my $conn = PVE::APIClient::Config->remote_conn($config, $remote);

    my $resource = PVE::APIClient::Helpers::get_vmid_resource($conn, $vmid);

    my $upid = $conn->post("api2/json/nodes/$resource->{node}/$resource->{type}/$resource->{vmid}/status/$cmd", $param);

    print PVE::APIClient::Helpers::poll_task($conn, $resource->{node}, $upid) . "\n";
};

__PACKAGE__->register_method ({
    name => 'start',
    path => 'start',
    method => 'POST',
    description => "Start a  guest (VM/Container).",
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

	my $remote = PVE::Tools::extract_param($param, 'remote');
	my $vmid = PVE::Tools::extract_param($param, 'vmid');

	$guest_status_command->($remote, $vmid, 'start', $param);

	return undef;
    }});

__PACKAGE__->register_method ({
    name => 'stop',
    path => 'stop',
    method => 'POST',
    description => "Stop a guest (VM/Container).",
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

	my $remote = PVE::Tools::extract_param($param, 'remote');
	my $vmid = PVE::Tools::extract_param($param, 'vmid');

	$guest_status_command->($remote, $vmid, 'stop', $param);

	return undef;
    }});

1;