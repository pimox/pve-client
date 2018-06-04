package PVE::APIClient::Config;

use strict;
use warnings;
use JSON;

use File::HomeDir ();
use PVE::Tools qw(file_get_contents file_set_contents);

sub new {
    my ($class) = @_;

    my $self = {
	file         => File::HomeDir::home() . '/.pveclient',
    };
    bless $self => $class;

    $self->load();

    return $self;
}

sub load {
    my ($self) = @_;

    if (-e $self->{file}) {
	my $filemode = (stat($self->{file}))[2] & 07777;
	if ($filemode != 0600) {
	    die sprintf "wrong permissions on '$self->{file}' %04o (expected 0600)\n", $filemode;
	}

	my $contents = file_get_contents($self->{file});
	$self->{data} = from_json($contents);
    } else {
	$self->{data} = {};
    }

    if (!exists($self->{data}->{remotes})) {
	$self->{data}->{remotes} = {};
    }

    # Verify config
    for my $name (@{$self->remote_names}) {
	my $cfg = $self->{data}->{remotes}->{$name};

	foreach my $opt (qw(host port username fingerprint)) {
	  die "missing option '$opt' (remote '$name')" if !defined($cfg->{$opt});
	}
    }
}

sub save {
    my ($self) = @_;

    my $contents = to_json($self->{data}, {pretty => 1, canonical => 1});
    file_set_contents($self->{file}, $contents, 0600);
}

sub add_remote {
    my ($self, $name, $host, $port, $fingerprint, $username, $password) = @_;

    $self->{data}->{remotes}->{$name} = {
	host => $host,
	port => $port,
	fingerprint => $fingerprint,
	username => $username,
    };

    if (defined($password)) {
	$self->{data}->{remotes}->{$name}->{password} = $password;
    }
}

sub remote_names {
    my ($self) = @_;

    return [keys %{$self->{data}->{remotes}}];
}

sub lookup_remote {
    my ($self, $name) = @_;

    die "Unknown remote \"$name\" given"
      if (!exists($self->{data}->{remotes}->{$name}));

    return $self->{data}->{remotes}->{$name};
}

sub remotes {
    my ($self) = @_;

    my $res = {};

    # Remove the password from each remote.
    for my $name ($self->remote_names) {
	my $cfg = $self->{data}->{remotes}->{$name};
	$res->{$name} = {
	    host        => $cfg->{host},
	    port        => $cfg->{port},
	    username    => $cfg->{username},
	    fingerprint => $cfg->{fingerprint},
	};
    }

    return $res;
}

sub remove_remote {
    my ($self, $remote) = @_;

    $self->lookup_remote($remote);

    delete($self->{data}->{remotes}->{$remote});

    $self->save();
}

sub remote_conn {
    my ($self, $remote) = @_;

    my $section = $self->lookup_remote($remote);
    my $conn = PVE::APIClient::LWP->new(
	username                => $section->{username},
	password                => $section->{password},
	host                    => $section->{host},
	port                    => $section->{port},
	cached_fingerprints     => {
	    $section->{fingerprint} => 1,
	}
    );

    $conn->login;

    return $conn;
}

1;
