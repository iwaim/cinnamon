package Cinnamon::DSL;
use strict;
use warnings;
use parent qw(Exporter);

use Cinnamon::Config;
use Cinnamon::Local;
use Cinnamon::Remote;
use Cinnamon::Logger;
use Term::ReadKey;

use Coro;

our @EXPORT = qw(
    set
    get
    role
    task

    remote
    run
    sudo
);

sub set ($$) {
    my ($name, $value) = @_;
    Cinnamon::Config::set $name => $value;
}

sub get ($@) {
    my ($name, @args) = @_;
    Cinnamon::Config::get $name, @args;
}

sub role ($$;$) {
    my ($name, $hosts, $params) = @_;
    $params ||= {};
    Cinnamon::Config::set_role $name => $hosts, $params;
}

sub task ($$) {
    my ($task, $task_def) = @_;

    Cinnamon::Config::set_task $task => $task_def;
}

sub remote (&$) {
    my ($code, $host) = @_;

    my $remote = Cinnamon::Remote->new(
        host => $host,
        user => Cinnamon::Config::user,
    );

    my $stash = _stash();
    local $stash->{current_host}   = $remote->host;
    local $stash->{current_remote} = $remote;

    $code->($host);
}

sub run (@) {
    my (@cmd) = @_;
    my $opt;
    $opt = shift @cmd if ref $cmd[0] eq 'HASH';

    my ($stdout, $stderr);
    my $result;

    log info => sprintf "[%s :: executing] %s", _current_host(), join(' ', @cmd);

    if ($opt && $opt->{sudo}) {
        my $password = Cinnamon::Config::get('password');
        $password = _sudo_password() unless (defined $password);
        $opt->{password} = $password;
    }

    if (my $remote = _current_remote()) {
        $result = $remote->execute($opt, @cmd);
    }
    else {
        $result = Cinnamon::Local->execute($opt, @cmd);
    }

    if ($result->{has_error}) {
        die sprintf "error status: %d", $result->{error};
    }

    return ($result->{stdout}, $result->{stderr});
}

sub sudo (@) {
    my (@cmd) = @_;
    my $tty = Cinnamon::Config::get('tty');
    run {sudo => 1, tty => !! $tty}, @cmd;
}

sub _sudo_password {
    my $password;
    print "Enter sudo password: ";
    ReadMode "noecho";
    chomp($password = ReadLine 0);
    Cinnamon::Config::set('password' => $password);
    ReadMode 0;
    print "\n";
    return $password;
}

sub _current_host {
    _stash()->{current_host} || 'localhost';
}
sub _current_remote {
    _stash()->{current_remote};
}

# thread safe stash
sub _stash {
    $Coro::current->{Cinnamon} ||= {};
}

!!1;
