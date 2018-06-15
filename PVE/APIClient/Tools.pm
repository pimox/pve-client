package PVE::APIClient::Tools;

use strict;
use warnings;
use POSIX qw(EINTR EEXIST EOPNOTSUPP);
use base 'Exporter';

use IO::File;
use Text::ParseWords;
use Fcntl qw(:DEFAULT :flock);
use Scalar::Util 'weaken';

our @EXPORT_OK = qw(
$IPV6RE
$IPV4RE
split_list
file_set_contents
file_get_contents
extract_param
);

my $IPV4OCTET = "(?:25[0-5]|(?:2[0-4]|1[0-9]|[1-9])?[0-9])";
our $IPV4RE = "(?:(?:$IPV4OCTET\\.){3}$IPV4OCTET)";
my $IPV6H16 = "(?:[0-9a-fA-F]{1,4})";
my $IPV6LS32 = "(?:(?:$IPV4RE|$IPV6H16:$IPV6H16))";

our $IPV6RE = "(?:" .
    "(?:(?:" .                             "(?:$IPV6H16:){6})$IPV6LS32)|" .
    "(?:(?:" .                           "::(?:$IPV6H16:){5})$IPV6LS32)|" .
    "(?:(?:(?:" .              "$IPV6H16)?::(?:$IPV6H16:){4})$IPV6LS32)|" .
    "(?:(?:(?:(?:$IPV6H16:){0,1}$IPV6H16)?::(?:$IPV6H16:){3})$IPV6LS32)|" .
    "(?:(?:(?:(?:$IPV6H16:){0,2}$IPV6H16)?::(?:$IPV6H16:){2})$IPV6LS32)|" .
    "(?:(?:(?:(?:$IPV6H16:){0,3}$IPV6H16)?::(?:$IPV6H16:){1})$IPV6LS32)|" .
    "(?:(?:(?:(?:$IPV6H16:){0,4}$IPV6H16)?::" .           ")$IPV6LS32)|" .
    "(?:(?:(?:(?:$IPV6H16:){0,5}$IPV6H16)?::" .            ")$IPV6H16)|" .
    "(?:(?:(?:(?:$IPV6H16:){0,6}$IPV6H16)?::" .                    ")))";

our $IPRE = "(?:$IPV4RE|$IPV6RE)";

sub run_with_timeout {
    my ($timeout, $code, @param) = @_;

    die "got timeout\n" if $timeout <= 0;

    my $prev_alarm = alarm 0; # suspend outer alarm early

    my $sigcount = 0;

    my $res;

    eval {
	local $SIG{ALRM} = sub { $sigcount++; die "got timeout\n"; };
	local $SIG{PIPE} = sub { $sigcount++; die "broken pipe\n" };
	local $SIG{__DIE__};   # see SA bug 4631

	alarm($timeout);

	eval { $res = &$code(@param); };

	alarm(0); # avoid race conditions

	die $@ if $@;
    };

    my $err = $@;

    alarm $prev_alarm;

    # this shouldn't happen anymore?
    die "unknown error" if $sigcount && !$err; # seems to happen sometimes

    die $err if $err;

    return $res;
}

# flock: we use one file handle per process, so lock file
# can be nested multiple times and succeeds for the same process.
#
# Since this is the only way we lock now and we don't have the old
# 'lock(); code(); unlock();' pattern anymore we do not actually need to
# count how deep we're nesting. Therefore this hash now stores a weak reference
# to a boolean telling us whether we already have a lock.

my $lock_handles =  {};

sub lock_file_full {
    my ($filename, $timeout, $shared, $code, @param) = @_;

    $timeout = 10 if !$timeout;

    my $mode = $shared ? LOCK_SH : LOCK_EX;

    my $lockhash = ($lock_handles->{$$} //= {});

    # Returns a locked file handle.
    my $get_locked_file = sub {
	my $fh = IO::File->new(">>$filename")
	    or die "can't open file - $!\n";

	if (!flock($fh, $mode|LOCK_NB)) {
	    print STDERR "trying to acquire lock...\n";
	    my $success;
	    while(1) {
		$success = flock($fh, $mode);
		# try again on EINTR (see bug #273)
		if ($success || ($! != EINTR)) {
		    last;
		}
	    }
	    if (!$success) {
		print STDERR " failed\n";
		die "can't acquire lock '$filename' - $!\n";
	    }
	    print STDERR " OK\n";
	}

	return $fh;
    };

    my $res;
    my $checkptr = $lockhash->{$filename};
    my $check = 0; # This must not go out of scope before running the code.
    my $local_fh; # This must stay local
    if (!$checkptr || !$$checkptr) {
	# We cannot create a weak reference in a single atomic step, so we first
	# create a false-value, then create a reference to it, then weaken it,
	# and after successfully locking the file we change the boolean value.
	#
	# The reason for this is that if an outer SIGALRM throws an exception
	# between creating the reference and weakening it, a subsequent call to
	# lock_file_full() will see a leftover full reference to a valid
	# variable. This variable must be 0 in order for said call to attempt to
	# lock the file anew.
	#
	# An externally triggered exception elsewhere in the code will cause the
	# weak reference to become 'undef', and since the file handle is only
	# stored in the local scope in $local_fh, the file will be closed by
	# perl's cleanup routines as well.
	#
	# This still assumes that an IO::File handle can properly deal with such
	# exceptions thrown during its own destruction, but that's up to perls
	# guts now.
	$lockhash->{$filename} = \$check;
	weaken $lockhash->{$filename};
	$local_fh = eval { run_with_timeout($timeout, $get_locked_file) };
	if ($@) {
	    $@ = "can't lock file '$filename' - $@";
	    return undef;
	}
	$check = 1;
    }
    $res = eval { &$code(@param); };
    return undef if $@;
    return $res;
}


sub lock_file {
    my ($filename, $timeout, $code, @param) = @_;

    return lock_file_full($filename, $timeout, 0, $code, @param);
}

sub file_set_contents {
    my ($filename, $data, $perm)  = @_;

    $perm = 0644 if !defined($perm);

    my $tmpname = "$filename.tmp.$$";

    eval {
	my ($fh, $tries) = (undef, 0);
	while (!$fh && $tries++ < 3) {
	    $fh = IO::File->new($tmpname, O_WRONLY|O_CREAT|O_EXCL, $perm);
	    if (!$fh && $! == EEXIST) {
		unlink($tmpname) or die "unable to delete old temp file: $!\n";
	    }
	}
	die "unable to open file '$tmpname' - $!\n" if !$fh;
	die "unable to write '$tmpname' - $!\n" unless print $fh $data;
	die "closing file '$tmpname' failed - $!\n" unless close $fh;
    };
    my $err = $@;

    if ($err) {
	unlink $tmpname;
	die $err;
    }

    if (!rename($tmpname, $filename)) {
	my $msg = "close (rename) atomic file '$filename' failed: $!\n";
	unlink $tmpname;
	die $msg;
    }
}

sub file_get_contents {
    my ($filename, $max) = @_;

    my $fh = IO::File->new($filename, "r") ||
	die "can't open '$filename' - $!\n";

    my $content = safe_read_from($fh, $max, 0, $filename);

    close $fh;

    return $content;
}

sub file_read_firstline {
    my ($filename) = @_;

    my $fh = IO::File->new ($filename, "r");
    return undef if !$fh;
    my $res = <$fh>;
    chomp $res if $res;
    $fh->close;
    return $res;
}

sub safe_read_from {
    my ($fh, $max, $oneline, $filename) = @_;

    $max = 32768 if !$max;

    my $subject = defined($filename) ? "file '$filename'" : 'input';

    my $br = 0;
    my $input = '';
    my $count;
    while ($count = sysread($fh, $input, 8192, $br)) {
	$br += $count;
	die "$subject too long - aborting\n" if $br > $max;
	if ($oneline && $input =~ m/^(.*)\n/) {
	    $input = $1;
	    last;
	}
    }
    die "unable to read $subject - $!\n" if !defined($count);

    return $input;
}

sub split_list {
    my $listtxt = shift || '';

    return split (/\0/, $listtxt) if $listtxt =~ m/\0/;

    $listtxt =~ s/[,;]/ /g;
    $listtxt =~ s/^\s+//;

    my @data = split (/\s+/, $listtxt);

    return @data;
}

# split an shell argument string into an array,
sub split_args {
    my ($str) = @_;

    return $str ? [ Text::ParseWords::shellwords($str) ] : [];
}

sub extract_param {
    my ($param, $key) = @_;

    my $res = $param->{$key};
    delete $param->{$key};

    return $res;
}

1;
