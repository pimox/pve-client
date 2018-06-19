package PVE::APIClient::Commands::GuestStatus;

use strict;
use warnings;

use PVE::APIClient::Helpers;
use PVE::APIClient::Config;

use PVE::APIClient::JSONSchema qw(get_standard_option);

use File::Temp qw(tempfile);

use PVE::APIClient::CLIHandler;

use base qw(PVE::APIClient::CLIHandler);

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

	my $remote = PVE::APIClient::Tools::extract_param($param, 'remote');
	my $vmid = PVE::APIClient::Tools::extract_param($param, 'vmid');

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
	    timeout => {
		description => "Timeout in seconds",
		type => 'integer',
		minimum => 1,
		optional => 1,
	    },
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	my $remote = PVE::APIClient::Tools::extract_param($param, 'remote');
	my $vmid = PVE::APIClient::Tools::extract_param($param, 'vmid');

	$guest_status_command->($remote, $vmid, 'stop', $param);

	return undef;
    }});

__PACKAGE__->register_method ({
    name => 'shutdown',
    path => 'shutdown',
    method => 'POST',
    description => "Stop a guest (VM/Container).",
    parameters => {
	additionalProperties => 0,
	properties => {
	    remote => get_standard_option('pveclient-remote-name'),
	    vmid => get_standard_option('pve-vmid'),
	    force => {
		description => "Make sure the Container/VM stops.",
		type => 'boolean',
		optional => 1,
	    },
	    timeout => {
		description => "Timeout in seconds",
		type => 'integer',
		minimum => 1,
		optional => 1,
	    },
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	my $remote = PVE::APIClient::Tools::extract_param($param, 'remote');
	my $vmid = PVE::APIClient::Tools::extract_param($param, 'vmid');

	$guest_status_command->($remote, $vmid, 'shutdown', $param);

	return undef;
    }});

__PACKAGE__->register_method ({
    name => 'suspend',
    path => 'suspend',
    method => 'POST',
    description => "Suspend a guest VM.",
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

	my $remote = PVE::APIClient::Tools::extract_param($param, 'remote');
	my $vmid = PVE::APIClient::Tools::extract_param($param, 'vmid');

	$guest_status_command->($remote, $vmid, 'suspend', $param);

	return undef;
    }});

__PACKAGE__->register_method ({
    name => 'resume',
    path => 'resume',
    method => 'POST',
    description => "Resume a guest VM.",
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

	my $remote = PVE::APIClient::Tools::extract_param($param, 'remote');
	my $vmid = PVE::APIClient::Tools::extract_param($param, 'vmid');

	$guest_status_command->($remote, $vmid, 'resume', $param);

	return undef;
    }});

__PACKAGE__->register_method ({
    name => 'spice',
    path => 'spice',
    method => 'POST',
    description => "Run the spice client for a guest (VM/Container)",
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

	my $remote = PVE::APIClient::Tools::extract_param($param, 'remote');
	my $vmid = PVE::APIClient::Tools::extract_param($param, 'vmid');

	my $config = PVE::APIClient::Config->load();
	my $conn = PVE::APIClient::Config->remote_conn($config, $remote);

	my $resource = PVE::APIClient::Helpers::get_vmid_resource($conn, $vmid);

	my $res = $conn->post("api2/json/nodes/$resource->{node}/$resource->{type}/$resource->{vmid}/spiceproxy", {});

	my $vvsetup = "[virt-viewer]\n";
	foreach my $k (keys %$res) {
	    $vvsetup .= "$k=$res->{$k}\n";
	}

	my ($fh, $filename) = tempfile( "tempXXXXX", SUFFIX => '.vv', TMPDIR => 1);
	syswrite($fh, $vvsetup);

	system("nohup remote-viewer $filename 1>/dev/null 2>&1 &");
	if ($? != 0) {
	    print "failed to execute remote-viewer: $!\n";
	}

	return undef;
    }});

1;
