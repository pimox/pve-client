package PVE::APIClient::Config;

use strict;
use warnings;
use JSON;
use File::Basename qw(dirname);
use File::Path qw(make_path);

use PVE::APIClient::Helpers;
use PVE::APIClient::JSONSchema;
use PVE::APIClient::SectionConfig;
use PVE::APIClient::PTY;
use PVE::APIClient::Tools qw(file_get_contents file_set_contents);

use base qw(PVE::APIClient::SectionConfig);

my $remote_namne_regex = qw(\w+);

my $defaults_section = '!DEFAULTS';

my $complete_remote_name = sub {

    my $config = PVE::APIClient::Config->load();
    my $list = [];
    foreach my $name (keys %{$config->{ids}}) {
	push @$list, $name if $name ne $defaults_section;
    }
    return $list;
};

PVE::APIClient::JSONSchema::register_standard_option('pveclient-output-format', {
    type => 'string',
    description => 'Output format.',
    enum => [ 'text', 'json' ],
    optional => 1,
    default => 'text',
});

PVE::APIClient::JSONSchema::register_standard_option('pveclient-remote-name', {
    description => "The name of the remote.",
    type => 'string',
    pattern => $remote_namne_regex,
    completion => $complete_remote_name,
});

my $defaultData = {
    propertyList => {
	type => {
	    description => "Section type.",
	    optional => 1,
	},
    },
};

sub private {
    return $defaultData;
}

sub config_filename {
    my ($class) = @_;

    my $dir = PVE::APIClient::Helpers::configuration_directory();

    return "$dir/config";
}

sub format_section_header {
    my ($class, $type, $sectionId, $scfg, $done_hash) = @_;

    if ($type eq 'defaults') {
	return "defaults:\n";
    } else {
	return "$type: $sectionId\n";
    }
}

sub parse_section_header {
    my ($class, $line) = @_;

    if ($line =~ m/^defaults:\s*$/) {
	return ('defaults', $defaults_section, undef, {});
    } elsif ($line =~ m/^(\S+):\s*(\S+)\s*$/) {
	my ($type, $name) = (lc($1), $2);
	eval {
	    die "invalid remote name '$name'\n"
		if $name eq $defaults_section || $name !~ m/^$remote_namne_regex$/;
	};
	return ($type, $name, $@, {});
    }
    return undef;
}

sub load {
    my ($class) = @_;

    my $filename = $class->config_filename();

    my $raw = '';

    if (-e $filename) {
	my $filemode = (stat($filename))[2] & 07777;
	if ($filemode != 0600) {
	    die sprintf "wrong permissions on '$filename' %04o (expected 0600)\n", $filemode;
	}

	$raw = file_get_contents($filename);
    }

    return $class->parse_config($filename, $raw);
}

sub save {
    my ($class, $cfg) = @_;

    my $filename = $class->config_filename();

    make_path(dirname($filename));

    $cfg->{order}->{$defaults_section} = -1; # write as first section
    my $raw = $class->write_config($filename, $cfg);

    file_set_contents($filename, $raw, 0600);
}

sub get_defaults {
    my ($class, $cfg) = @_;

    $cfg->{ids}->{$defaults_section} //= {};

    return $cfg->{ids}->{$defaults_section};
}

sub lookup_remote {
    my ($class, $cfg, $name, $noerr) = @_;

    my $data = $cfg->{ids}->{$name};

    return $data if $noerr || defined($data);

    die "unknown remote \"$name\"\n";
}

sub remote_conn {
    my ($class, $cfg, $remote) = @_;

    my $section = $class->lookup_remote($cfg, $remote);

    my $trylogin = sub {
	my ($ticket_or_password) = @_;

	if (!defined($ticket_or_password)) {
	    $ticket_or_password = PVE::APIClient::PTY::read_password("Remote password: ")
	}

	my $setup = {
	    username                => $section->{username},
	    password                => $ticket_or_password,
	    host                    => $section->{host},
	    port                    => $section->{port} // 8006,
	    cached_fingerprints     => {
		$section->{fingerprint} => 1,
	    }
	};

	my $conn = PVE::APIClient::LWP->new(%$setup);

	$conn->login();

	return $conn;
    };

    my $password = $section->{password};

    my $conn;

    if (defined($password)) {
	$conn = $trylogin->($password);
    } else {

	if (my $ticket = PVE::APIClient::Helpers::ticket_cache_lookup($remote)) {
	    eval { $conn = $trylogin->($ticket); };
	    if (my $err = $@) {
		PVE::APIClient::Helpers::ticket_cache_update($remote, undef);
		if (ref($err) && (ref($err) eq 'PVE::APIClient::Exception') && ($err->{code} == 401)) {
		    $conn = $trylogin->();
		} else {
		    die $err;
		}
	    }
	} else {
	    $conn = $trylogin->();
	}
    }

    PVE::APIClient::Helpers::ticket_cache_update($remote, $conn->{ticket});

    return $conn;
}

package PVE::APIClient::RemoteConfig;

use strict;
use warnings;

use PVE::APIClient::JSONSchema qw(register_standard_option get_standard_option);
use PVE::APIClient::SectionConfig;

use base qw( PVE::APIClient::Config);

sub type {
    return 'remote';
}

sub properties {
    return {
	name => get_standard_option('pveclient-remote-name'),
	host => {
	    description => "The host.",
	    type => 'string', format => 'address',
	    optional => 1,
	},
	username => {
	    description => "The username.",
	    type => 'string',
	    optional => 1,
	},
	password => {
	    description => "The users password.",
	    type => 'string',
	    optional => 1,
	},
	port => {
	    description => "The port.",
	    type => 'integer',
	    optional => 1,
	    default => 8006,
	},
	fingerprint => {
	    description => "Fingerprint.",
	    type => 'string',
	    optional => 1,
	},
	comment => {
	    description => "Description.",
	    type => 'string',
	    optional => 1,
	    maxLength => 4096,
	},
    };
}

sub options {
    return {
	name => { optional => 0 },
	host => { optional => 0 },
	comment => { optional => 1 },
	username => { optional => 0 },
	password => { optional => 1 },
	port => { optional => 1 },
	fingerprint => { optional => 1 },
   };
}

__PACKAGE__->register();


package PVE::APIClient::DefaultsConfig;

use strict;
use warnings;

use PVE::APIClient::JSONSchema qw(register_standard_option get_standard_option);

use base qw( PVE::APIClient::Config);


sub type {
    return 'defaults';
}

sub options {
    return {
	name => { optional => 1 },
	username => { optional => 1 },
	port => { optional => 1 },
   };
}

__PACKAGE__->register();


PVE::APIClient::Config->init();

1;
