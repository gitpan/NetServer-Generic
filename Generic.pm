#!/usr/bin/perl

package NetServer::Generic;

$VERSION = "0.02";

=pod

=head1 NAME

Server - simple TCP/IP server (forking and non-forking)

=head1 SYNOPSIS

  my $server_cb = sub  {
                         my ($s) = shift ;
                         print STDOUT "Echo server: type bye to quit, exit ",
                                      "to kill the server.\n\n" ;
                         while (defined ($tmp = <STDIN>)) {
                             return if ($tmp =~ /^bye/i);
                             $s->quit() if ($tmp =~ /^exit/i);
                             print STDOUT "You said:>$tmp\n";
                       }                            
  my ($foo) = new Server;
  $foo->port(9000);
  $foo->callback($server_cb);
  $foo->mode("forking");
  print "Starting server\n";
  $foo->run();

=head1 DESCRIPTION

C<Server> provides a (very) simple server daemon for TCP/IP
processes. It is intended to free the programmer from having to think
too hard about networking issues so that they can concentrate on 
doing something useful.

The C<Server> object accepts the following methods, which configure
various aspects of the new server:

=over 4

=item port

The port to listen on.

=item hostname

The local address to bind to. If no address is specified, listens for
any connection on the designated port.

=item listen

Queue size for listen.

=item proto

Protocol we're listening to (defaults to tcp)

=item timeout

Timeout value (see L<IO::Socket::INET>)

=item allowed

list of IP addresses or hostnames that are explicitly allowed to connect
to the server. If empty, the default policy is to allow connections from
anyone not in the 'forbidden' list.

NOTE: IP addresses or hostnames may be specified as perl regular
expressions; for example 154\.153\.4\..* matches any IP address
beginning with '154.153.4.';
.*antipope\.org matches any hostname in the antipope.org domain.

=item forbidden

list of IP addresses or hostnames that are refused permission to
connect to the server. If empty, the default policy is to refuse
connections from anyone not in the 'allowed' list (unless the
allowed list is empty, in which case anyone may connect).

=item callback

Coderef to a subroutine which handles incoming connections (called
with one parameter -- a C<Server> object which can be used to shut
down the session).

=item mode

Can be one of B<forking>, B<select>, B<client>, B<threaded>, or B<inetd>.
(B<threaded> and B<inetd> are not yet implemented and doesn't do
anything!) If B<forking> mode is selected, the server handles
requests by forking a child process to service them. If B<select>
mode is selected, the server uses the C<IO::Select> class to
implement a simple non-forking server. (NB: This is not recommended
for slow or resource-intensive servers, but may be useful for
servers that provide access to some kind of shared resource for
other processes, where the resource may be held in memory).

The B<client> mode is special; it indicates that rather than sitting
around waiting for an incoming connection, the server is itself a
TCP/IP client. In client mode, C<hostname> is the B<remote> host to
connect to and C<port> is the remote port to open. The callback
routine is used, as elsewhere, but it should be written as for a
client -- i.e. it should issue a request or command, then read.
An additional method exists for client mode: C<trigger>. C<trigger>
expects a coderef as a parameter. This coderef is executed
before the client-mode server spawns a child; if it returns a non-zero
value the child is forked and opens a client connection to the target
host, otherwise the server exits. The trigger method may be used to
sleep for a random interval then return 1 (so that repeated clients
are spawned at random intervals), or fork several children (on a one-
time-only basis) then work as above (so that several clients poke at
the target server on a random basis). The default trigger method 
returns 1 immediately the first time it is called, then returns 0 --
this means that the client makes a single connection to the target
host, invokes the callback routine, then exits. (See the test examples
which come with this module for examples of how to use client mode.) 

Note that client mode relies on the fork() system call.

The B<threaded> mode indicates that multithreading will be used
to service requests; code to support this doesn't exist yet (and
requires Perl 5.005 or higher and a native threads library to run,
so it's not 100% portable). The B<inetd> mode indicates that the
server will run as a daemon from B<inetd>, rather than standalone;
it implies that the B<run()> method will install(!) the server on
the host system's inetd configuration and re-start inetd. (This
doesn't exist yet, either, and is only suitable for stable,
high-throughput systems in heavy production use.)

By default, B<forking> mode is selected.

=back

Of these, the C<callback> method is most important; it specifies
a reference to a subroutine which effectively does whatever the
server does.

A callback subroutine is a normal Perl subroutine. It is invoked
with STDIN and STDOUT attached to an C<IO::Socket::INET> object,
so that reads from STDIN get information from the client, and writes
to STDOUT send information to the client. Note that both STDIN and
STDOUT are unbuffered. In addition, a C<Server> object is passed
as an argument (but the C<callback> is free to ignore it).

Your server reads and writes data via the socket as if it is the
standard input and standard output filehandles; for example:

  while (defined ($tmp = <STDIN>)) {  # read a line from the socket

  print STDOUT "You said: $tmp\n";    # print something to the socket

(See C<IO::Handle> and C<IO::Socket> for more information on this.)

If you're not familiar with sockets, don't get too fresh and try to 
close or seek on STDIN or STDOUT; just treat them like a file.

The server object is not strictly necessary in the callback, but comes
in handy: you can shut down the server completely by calling the 
C<quit()> method.
 
When writing a callback subroutine, remember to define some condition under 
which you return! 

Here's a slightly more complex server example:


 # minimal http server (HTTP/0.9):
 # this is a REALLY minimal HTTP server. It only understands GET
 # requests, does no header parsing whatsoever, and doesn't understand
 # relative addresses! Nor does it understand CGI scripts. And it ain't
 # suitable as a replacement for Apache (at least, not any time soon :).
 # The base directory for the server and the default
 # file name are defined in B<url_to_file()>, which maps URLs to
 # absolute pathnames. The server code itself is defined in the
 # closure B<$http>, which shows how simple it is to write a server
 # using this module.

 sub url_to_file($) {
   # for a given URL, turn it into an absolute pathname
   my ($u) = shift ;  # incoming URL fragment from GET request
   my ($f) = "";      # file pathname to return
   my ($htbase) = "/usr/local/etc/httpd/docs/";
   my ($htdefault) = "index.html";
   chop $u;
   if ($u eq "/") {
       $f = $htbase . $htdefault;
       return $f;
   } else {
       if ($u =~ m|^/.+|) {
           $f = $htbase;  chop $f;
           $f .= $u;
       } elsif ($u =~ m|[^/]+|) {
           $f = $htbase . $u;
       }
       if ($u =~ m|.+/$|) {
           $f .= $htdefault;
       }
       if ($f =~ /\.\./) {
           my (@path) = split("/", $f);
           my ($buff, $acc) = "";
           shift @path;
           while ($buff = shift @path) {
               my ($tmp) = shift @path;
               if ($tmp ne '..') {
                   unshift @path, $tmp;
                   $acc .= "/$buff";
               }
           }
           $f = $acc;
       }
   }
   return $f;
 }

 my ($http) = sub {
    my ($fh) = shift ;
    while (defined ($tmp = <STDIN>)) {
        chomp $tmp;
        if ($tmp =~ /^GET\s+(.*)$/i) {
            $getfile = $1;
	    $getfile = url_to_file($getfile);
            print STDERR "Sending $getfile\n";
            my ($in) = new IO::File();
            if ($in->open("<$getfile") ) {
                $in->autoflush(1);
                print STDOUT "Content-type: text/html\n\n";
                while (defined ($line = <$in>)) {
                    print STDOUT $line;
                }
            } else {
                print STDOUT "404: File not found\n\n";
            }
        }
        return 0;
    }
 };                           

 # main program starts here

 my (%config) =  ("port"     => 9000, 
                  "callback" => $http, 
		  "hostname" => "public.antipope.org");

 my ($allowed) = ['.*antipope\.org', 
 		 '.*localhost.*'];

 my ($forbidden) = [ '194\.205\.10\.2'];

 my ($foo) = new Server(%config); # create new http server bound to port 
                                  # 9000 of public.antipope.org
 $foo->allowed($allowed);         # who is allowed to connect to us
 $foo->forbidden($forbidden);     # who is refused access
 print "Starting http server on port 9000\n";
 $foo->run();                     
 exit 0;


=head2 Additional methods

C<NetServer::Generic> provides a couple of extra methods.

=over 4

=item peer()

The B<peer()> method returns a reference to a two-element list containing 
the hostname and IP address of the host at the other end of the socket.
If called before a connection has been received, its value will be undefined.
(Don't try to assign values via B<peer> unless you want to confuse the 
allowed/forbidden checking code!)

=back

=item quit()

The B<quit()> method attempts to shut down a server. If running as a forking
service, it does so by sending a kill -15 to the parent process. If running
as a select-based service it returns from B<run()>.


=head2 Types of server

A full discussion of internet servers is well beyond the scope of this man
page. Beginners may want to start with a source like L<Beginning Linux 
Programming> (which provides a simple, lucid discussion); more advanced
readers may find Stevens' L<Advanced Programming in the UNIX environment>
useful.

In general, on non-threaded systems, a forking server is slightly less
efficient than a select-based server (and uses up lots of PIDs). On the other
hand, a select-based server is not a good solution to high workloads or
time-consuming processes such as providing an NNTP news feed to an online
newsreader.

A major issue with the select-based server code in this release is that
the IO::Select based server cannot know that a socket is ready until some 
data is received over it. (It calls B<can_read()> to detect sockets waiting
to be read from.) Thus, it is not suitable for writing servers like
which emit status information without first reading a request.


=head1 SEE ALSO

L<IO::Handle>,
L<IO::Socket>,
L<LWP>,
L<perlfunc>,
L<perlop/"I/O Operators">

=head1 HISTORY

=over 4

=item Version 0.1 

Based on the simple forking server in Chapter 10 of "Advanced Perl 
Programming" by Sriram Srinivasan, with a modular wrapper to make 
it easy to use and configure, and a rudimentary access control system.

=item Version 0.2

Added the B<peer()> method to provide peer information.

Bugfix to B<ok_to_serve> from Marius Kjeldahl I<marius@ace.funcom.com>.

Added select-based server code, B<mode> method to switch between forking
and selection server modes.

Updated test code (should do something now!)

Added example: fortune server and client code.

Supports NetServer::SMTP (and, internally, NetServer::vTID).

=back


=cut

use Carp;
use IO::File;
use IO::Socket;
use IO::Handle;
use IO::Select;
use Socket;

# NetServer::FieldTypes contains a hash of autoload method names, and the 
# type of parameter they expect. For example, NetServer->callback() takes
# a coderef as a parameter; AUTOLOAD needs to know this so it can whine
# about incorrect parameter types.

$NetServer::FieldTypes = {
                         "port" => "scalar",
                         "callback" => "code",
                         "listen" => "scalar",
                         "proto" => "scalar",
                         "hostname" => "scalar",
                         "timeout" => "scalar",
                         "root_pid" => "scalar",
                         "allowed" => "array",
                         "forbidden" => "array",
                         "peer" => "array",
                         "mode" => "scalar",
                         "trigger" => "code",
                      };

# $NetServer::Debug; if non-zero, emit some debugging info on STDERR

$NetServer::Debug = 0;

# here is a default callback routine. It basically echoes back anything
# you sent to the server, unless the line begins with quit, bye, or
# exit -- in which case it kills the server (rather than simply exiting).

$NetServer::default_cb = sub  {
                             my ($s) = shift;
                             print STDOUT "Echo server: type bye to quit, ",
                                          "exit to kill the server.\n\n" ;
                             while (defined ($tmp = <STDIN>)) {
                                 return if ($tmp =~ /^bye/i);
                                 $s->quit() if ($tmp =~ /^exit/i);
                                 print STDOUT "You said:>$tmp\n";
                             }                            
                          };
# Methods

sub new {
    my ($class) = shift if @_;
    my ($self) = {"listen" => 5,
                  "timeout" => 60,
                  "hostname" => "localhost",
                  "proto" => "tcp",
                  "callback" => $NetServer::default_cb,
                  "version" => $NetServer::Generic::VERSION,
                 };
    $self->{tags} = $NetServer::FieldTypes;
    bless $self, ($class or "Server");
    if (@_) {
        my (%tmp) = @_; my ($field) = "";
        foreach $field (keys %tmp) {
            $self->$field($tmp{$field});
        }
    }
    return $self;
}

sub VERSION {
    my $self = shift;
    return $self->{version};
}

sub run_select {
    my $self = shift;
    my ($main_sock) = 
        new IO::Socket::INET( # LocalAddr => $self->hostname(),
                              LocalPort => $self->port(),
                              Listen    => $self->listen(),
                              Proto     => $self->proto(),
                              Reuse     => 1
                            );
    die "Socket could not be created: $!\n" unless ($main_sock);
    $NetServer::Debug && print STDERR "Created socket\n";
    my $rh = new IO::Select($main_sock);
    $NetServer::Debug && print STDERR "Created IO::Select()\n";
    my (@ready) = ();
    while (@ready = $rh->can_read()) {
        my ($sock) = "";
        foreach $sock (@ready) {
            if ($sock == $main_sock) {
                my ($new_sock) = $sock->accept();
                $new_sock->autoflush(1);
                $rh->add($new_sock);
                if (! $self->ok_to_serve($new_sock)) {
                    $rh->remove($sock);
                    close($sock);
                }
            } else {
                if (! eof($sock)) {
                    $sock->autoflush(1);
                    my ($code) = $self->callback();
                    $self->sock($sock);
                    *STDIN = $sock;
                    *STDOUT = $sock;
                    select STDIN; $| = 1;
                    select STDOUT; $| = 1;
                    &$code($self);
                    $rh->remove($sock);
                    close $sock;
                    # shutdown($sock, 2);
                } else {
                    $rh->remove($sock);
                    close($sock);
                }
            }
        }
    }
}

sub run_fork {
    my ($self) = shift ;
    my ($main_sock) = 
        new IO::Socket::INET( # LocalAddr => $self->hostname(),
                              LocalPort => $self->port(),
                              Listen    => $self->listen(),
                              Proto     => $self->proto(),
                              Reuse     => 1
                            );

    die "Socket could not be created: $!\n" unless ($main_sock);


    # we need to trap SIGKILL and SIGINT. If no traps are already
    # defined by the user, add some default ones.
    if (! exists $SIG{INT}) {
       $SIG{INT} = sub { 
                          print STDERR "\nSIGINT: server $$ ",
                                       "shutting down \n"; 
                          exit 0;
                       };
    }
    # and make sure we wait() on children
    $SIG{CHLD} = sub { wait() };

    # now loop, forking whenever a new connection arrives on the listener
    $self->root_pid($$);  # set server root PID
    while (my ($new_sock) = $main_sock->accept()) {
        # my $now = strftime("%c ",localtime(time));
        my $pid = fork();
        die "Cannot fork: $!\n" unless defined ($pid);
        if ($pid == 0) {
            # child
            if ($self->ok_to_serve($new_sock)) {
                $new_sock->autoflush(1);
                my ($code) = $self->callback();
                *STDIN = $new_sock;
                *STDOUT = $new_sock;
                select STDIN; $| = 1;
                select STDOUT; $| = 1;
    	        &$code($self);
            }
            $NetServer::Debug && print STDERR "$0:$$: end of transaction\n";
            shutdown($new_sock, 2);
            exit 0;
        } else {
            # parent
            $NetServer::Debug && print STDERR "$0:$$: forked $pid\n";
        }
    }
}

sub run_client {
    my ($self) = shift ;
    $SIG{CHLD} = sub { wait() };
    
    # despatcher is a routine that dictates how often and how fast the
    # server forks and execs the test callback. The default sub (below)
    # returns immediately but is only true once, so the test is executed
    # immediately one time only. More realistic despatchers may sleep for
    # a random interval or even pre-fork themselves (for added chaos).
    my $despatcher = $self->trigger()  || sub { $j++; 
                                                return(($j > 1) ? 0 : 1 );
                                              };

    my $code = $self->callback();      # sub to call in child process
    $self->root_pid($$);               # set server root PID
    my $triggerval = &$despatcher;
    while (($triggerval ne "") && ($triggerval ne "0")) {
        # loop, forking to create new client sessions
        my $pid = fork();
        die "Cannot fork: $!\n" unless defined ($pid);
        if ($pid == 0) {
            # child
            my ($sock) = 
                new IO::Socket::INET( PeerAddr => $self->hostname(),
                                      PeerPort => $self->port(),
                                      Proto     => $self->proto(),
                                    );
            die "Socket could not be created: $!\n" unless ($sock);
            *STDIN = $sock;
            *STDOUT = $sock;
            select STDIN; $| = 1;
            select STDOUT; $| = 1;
            &$code($self, $triggerval);
            shutdown($sock, 2);
            exit 0;
        } else {
            # in parent
            $NetServer::Debug && print STDERR "$0:$$: forked $pid\n";
            $triggerval = &$despatcher;
        }
    }
    wait; # for last child
    return;
}

sub run {
    my $self = shift;
    $NetServer::Debug && print STDERR "run() ...\n";
    if ( (! defined ($self->mode())) || (lc($self->mode()) eq "forking")) {
        $self->run_fork();
    } elsif ( lc($self->mode()) eq "select") {
        $self->run_select();
    } elsif ( lc($self->mode()) eq "client") {
        $self->run_client();
    } else {
        my $aargh = "Unknown mode: " . $self->mode() . "\n";
        die $aargh;
    }
    return;
}

sub ok_to_serve($$) {
    # internal sub. Given a ref to a Server object, and an IO::Socket::INET,
    # see if we are allowed to serve the request. Return 1 if it's okay, 0
    # otherwise.
    my ($self, $new_sock) = @_;
    my ($junk, $peerp) = unpack_sockaddr_in($new_sock->peername());
    my ($peername) = gethostbyaddr($peerp, AF_INET);
    my ($peeraddr) = join(".", unpack("C4", $new_sock->peeraddr()));
    $self->peer([ $peername, $peeraddr]);
    $NetServer::Debug &&
        print STDERR "$0:$$: request from ", join(" ", @{$self->peer()}), "\n"; 
    return 1 if ((! defined($self->forbidden())) && 
                 (! defined($self->allowed())));
    #
    # if we got here, forbidden or allowed are not undef, 
    # so we have to do some checking
    # Now we have the originator's hostname and IP address, we check
    # them against the allowed list and the forbidden list. 
    my ($found_allowed, $found_banned) = 0;
    ALLOWED:
    foreach (@{ $self->allowed() }) {
        next if (! defined($_));
        if (($peername =~ /$_/i) || ($peeraddr =~ /$_/i)) {
            $found_allowed++;
            $NetServer::Debug && 
                print STDERR "allowed: $_ matched $peername or $peeraddr\n";
            last ALLOWED;
        }
    }
    FORBIDDEN:
    foreach (@{ $self->forbidden() } ) {
        next if (! defined($_));
        if (($peername =~ /$_/i) || ($peeraddr =~ /$_/i)) {
            $found_banned++;
            $NetServer::Debug && 
                print STDERR "forbidden: $_ matched $peername or $peeraddr\n";
            last FORBIDDEN;
        }
    }
    ($found_banned && ! $found_allowed) && return 0;
    ($found_allowed && ! $found_banned) && return 1;
    ($found_allowed && $found_banned)   && return 0;
    return 0;
}

sub quit {
    my ($self) = shift;
    if (@_) { 
        $tmp = shift; 
        $self->root_pid($tmp); 
    }
    print STDERR "called shutdown() (root pid is ", $self->root_pid(), ")\n";
    kill 15, $self->root_pid();
    exit;
}

sub AUTOLOAD {
    my ($self) = shift;
    my ($name) = $AUTOLOAD;
    $NetServer::Debug && print STDERR "AUTOLOAD::$name(@_)\n";
    $name =~ s/.*://;
    if (@_) {
        my ($val) = shift;
        # rudimentary type checking
        my ($r) = (ref($val) || "scalar");
        if (! exists ($self->{tags}->{$name})) {
            warn "\tno such method: $name\n";
            return undef;
        }
        if ($r !~ /$self->{tags}->{$name}/i) {
            warn "\t", ref($val), ": expecting a ", 
                 $self->{tags}->{$name}, "\n", "\tgot [", 
                 join("][", @_), "]\n";
            return undef;
        }
        return $self->{$name} = $val;
    } else {
        return $self->{$name};
    }
}

1;

