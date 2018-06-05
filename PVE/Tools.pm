package PVE::Tools;

use strict;
use warnings;
use POSIX qw(EINTR EEXIST EOPNOTSUPP);
use base 'Exporter';

use IO::File;
use Text::ParseWords;

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
