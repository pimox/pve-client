package PVE::APIClient::Commands::list;

use strict;
use warnings;
use JSON;

use PVE::JSONSchema qw(get_standard_option);

use base qw(PVE::CLIHandler);

__PACKAGE__->register_method ({
    name => 'list',
    path => 'list',
    method => 'GET',
    description => "List containers.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    remote => get_standard_option('pveclient-remote-name'),
	    format => {
		type => 'string',
		description => 'Output format',
		enum => [ 'table', 'json' ],
		optional => 1,
		default => 'table',
	    }
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	my $config = PVE::APIClient::Config->load();
	my $conn = PVE::APIClient::Config->remote_conn($config, $param->{remote});
	my $resources = $conn->get('api2/json/cluster/resources', { type => 'vm' });

	if (!defined($param->{format}) or $param->{format} eq 'table') {
	    my $headers = ['Node', 'VMID', 'Type', 'Name', 'Status'];
	    my $data = [];
	    for my $el (@$resources) {
		push(@$data, [$el->{node}, $el->{vmid}, $el->{type}, $el->{name}, $el->{status}]);
	    }

	    printf("%10s %10s %10s %10s %10s\n", @$headers);
	    for my $row (@$data) {
		printf("%10s %10s %10s %10s %10s\n", @$row);
	    }
	} else {
	    print JSON::to_json($resources, {utf8 => 1, pretty => 1});
	}

	return undef;
    }});


our $cmddef = [ __PACKAGE__, 'list', ['remote']];

1;