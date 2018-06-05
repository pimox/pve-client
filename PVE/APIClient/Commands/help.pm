package PVE::APIClient::Commands::help;

use strict;
use warnings;

use PVE::APIClient::Commands::help;
use PVE::APIClient::Commands::lxc;
use PVE::APIClient::Commands::remote;

use PVE::CLIHandler;

use base qw(PVE::CLIHandler);

__PACKAGE__->register_method ({
    name => 'help',
    path => 'help',
    method => 'GET',
    description => "Print usage information.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    verbose => {
		description => "Verbose output - list all options.",
		type => 'boolean',
		optional => 1,
		default => 0,
	    },
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	my $text = "USAGE: pveclient <cmd> ...\n\n" if !$param->{verbose};

	my $format = $param->{verbose} ? 'full' : 'short';

	my $assemble_usage_string = sub {
	    my ($subcommand, $def) = @_;

	    my $sortfunc = sub { sort keys %{$_[0]} };

	    if (ref($def) eq 'HASH') {
		foreach my $cmd (&$sortfunc($def)) {

		    if (ref($def->{$cmd}) eq 'ARRAY') {
			my ($class, $name, $arg_param, $fixed_param) = @{$def->{$cmd}};
			$text .= $class->usage_str($name, "pveclient $subcommand $name", $arg_param, $fixed_param, $format, $class->can('read_password'));
		    }
		}
	    } else {
		my ($class, $name, $arg_param, $fixed_param) = @$def;
		$text .= $class->usage_str($name, "pveclient $name", $arg_param, $fixed_param, $format);
	    }
	};

	$assemble_usage_string->('help', $PVE::APIClient::Commands::help::cmddef);
	$assemble_usage_string->('lxc', $PVE::APIClient::Commands::lxc::cmddef);
	$assemble_usage_string->('remote', $PVE::APIClient::Commands::remote::cmddef);

	$text .= "pveclient <get/set/create/delete> <path> {options}\n\n";

	print STDERR $text;

	return undef;
    }});

our $cmddef = [ __PACKAGE__, 'help', []];

1;
