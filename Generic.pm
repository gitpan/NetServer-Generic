package NetServer::Generic;

$VERSION = "0.01";

=pod

=head1 NAME

Server - simple forking TCP/IP server

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
  print "Starting server\n";
  $foo->run();

=head1 DESCRIPTION

C<Server> provides a (very) simple forking server daemon for TCP/IP
processes. It is intended to free the programmer from having to think
too hard about networking issues so that they can concentrate on 
doing something useful.

The C<Server> object accepts the following methods, which configure
various aspects of the new server:

=over 4

=item port

The port to listen on

=item hostname

The local address to bind to

=item listen

Queue size for listen

=item proto

Protocol we're listening to (defaults to tcp)

=item timeout

Timeout value (see L<IO::Socket::INET>)

=item allowed

list of IP addresses or hostnames that are explicitly allowed to connect
to the server. If empty, the default policy is to allow connections from
anyone not in the 'forbidden' list.

NOTE: IP addresses or hostnames may be specified as perl regular expressions;
for example 154\.153\.4\..* matches any IP address beginning with '154.153.4.';
.*antipope\.org matches any hostname in the antipope.org domain.

=item forbidden

list of IP addresses or hostnames that are refused permission to connect
to the server. If empty, the default policy is to refuse connections from
anyone not in the 'allowed' list (unless the allowed list is empty, in
which case anyone may connect).

=item callback

Coderef to a subroutine which handles incoming connections (called with
one parameter -- a C<Server> object which can be used to shut down
the session).

=back

Of these, the C<callback> method is most important; it specifies a
reference to a subroutine which effectively does whatever the
server does.

A callback subroutine is a normal Perl subroutine. It is invoked
with STDIN and STDOUT attached to an C<IO::Socket::INET> object,
so that reads from STDIN get information from the client, and 
writes to STDOUT send information to the client. Note that both
STDIN and STDOUT are unbuffered. In addition, a C<Server> object
is passed as an argument (but the C<callback> is free to ignore
it).

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

=back


=cut

use Carp;
use IO::File;
use IO::Socket;
use Socket;
use Data::Dumper;

# Server::FieldTypes contains a hash of autoload method names, and the 
# type of parameter they expect. For example, Server->callback() takes
# a coderef as a parameter; AUTOLOAD needs to know this so it can whine
# about incorrect parameter types.

$Server::FieldTypes = {
                         "port" => "scalar",
                         "callback" => "code",
                         "listen" => "scalar",
                         "proto" => "scalar",
                         "hostname" => "scalar",
                         "timeout" => "scalar",
                         "root_pid" => "scalar",
                         "allowed" => "array",
                         "forbidden" => "array"
                      };

# $Server::Debug; if non-zero, emit some debugging info on STDERR

$Server::Debug = 1;

# here is a default callback routine. It basically echoes back anything
# you sent to the server, unless the line begins with quit, bye, or
# exit -- in which case it kills the server (rather than simply exiting).

$Server::default_cb = sub  {
                             my ($s) = shift;
                             print STDOUT "Echo server: type bye to quit, ",
                                          "exit to kill the server.\n\n" ;
                             while (defined ($tmp = <STDIN>)) {
                                 return if ($tmp =~ /^bye/i);
                                 $s->quit() if ($tmp =~ /^exit/i);
                                 $fh->print ("You said:>$tmp\n");
                             }                            
                          };
# Methods

sub new {
    my ($class) = shift if @_;
    my ($self) = {"listen" => 5,
                  "timeout" => 60,
                  "hostname" => "localhost",
                  "proto" => "tcp",
                  "callback" => $Server::default_cb,
                 };
    $self->{tags} = $Server::FieldTypes;
    bless $self, ($class or "Server");
    if (@_) {
        my (%tmp) = @_; my ($field) = "";
        foreach $field (keys %tmp) {
            $self->$field($tmp{$field});
        }
    }
    return $self;
}

sub run {
    my ($self) = shift ;
    my ($main_sock) = 
        new IO::Socket::INET( LocalAddr => $self->hostname(),
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
                          print STDERR "\nSIG$sig: server $$ ",
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
            $Server::Debug && print STDERR "$0:$$: end of transaction\n";
            shutdown($new_sock, 2);
            exit 0;
        } else {
            # parent
            $Server::Debug && print STDERR "$0:$$: forked $pid\n";
        }
    }
}

sub ok_to_serve($$) {
    # internal sub. Given a ref to a Server object, and an IO::Socket::INET,
    # see if we are allowed to serve the request. Return 1 if it's okay, 0
    # otherwise.
    my ($self, $new_sock) = @_;
    return 1 if (($self->forbidden() eq undef) && ($self->allowed() eq undef));
    #
    # if we got here, forbidden or allowed are not undef, 
    # so we have to do some checking
    my ($junk, $peerp) = unpack_sockaddr_in($new_sock->peername());
    my ($peername) = gethostbyaddr($peerp, AF_INET);
    my ($peeraddr) = join(".", unpack("C4", $new_sock->peeraddr()));
    $Server::Debug 
        && print STDERR "$0:$$: request from $peername [$peeraddr]\n";
    # Now we have the originator's hostname and IP address, we check
    # them against the allowed list and the forbidden list. 
    my ($found_allowed, $found_banned) = 0;
    ALLOWED:
    foreach (@{ $self->allowed() }) {
        next if ($_ eq undef);
        if (($peername =~ /$_/i) || ($peeraddr =~ /$_/i)) {
            $found_allowed++;
            $Server::Debug && 
                print STDERR "allowed: $_ matched $peername or $peeraddr\n";
            last ALLOWED;
        }
    }
    FORBIDDEN:
    foreach (@{ $self->forbidden() } ) {
        next if ($_ eq undef);
        if (($peername =~ /$_/i) || ($peeraddr =~ /$_/i)) {
            $found_banned++;
            $Server::Debug && 
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
    print "called shutdown()\n";
    kill 15, $self->root_pid();
    exit;
}

sub AUTOLOAD {
    my ($self) = shift;
    my ($name) = $AUTOLOAD;
    $name =~ s/.*://;
    if (@_) {
        my ($val) = shift;
        # rudimentary type checking
        my ($r) = (ref($val) || "scalar");
        if ($r !~ /$self->{tags}->{$name}/i) {
            warn ref($val), ": expecting a ", $self->{tags}->{$name}, "\n";
            return undef;
        }
        return $self->{$name} = $val;
    } else {
        return $self->{$name};
    }
}

1;

__END__

# ---- EXAMPLE #1 -- a minimal HTTP server in 70 lines of Perl -----------------

# minimal http server (HTTP/0.9):

sub url_to_file($) {
   # for a given URL, turn it into an absolute pathname
   my ($u) = shift ;    # incoming URL fragment from GET request
   my ($f) = "";        # file pathname to return
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
    while (defined ($tmp = <STDIN>)) {
        chomp $tmp;
        if ($tmp =~ /^GET\s+(.*)$/i) {
	    my ($getfile) = url_to_file($1);
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

my (%config) =  ("port" => 9000, 
                 "callback" => $http, 
                 "hostname" => "www.antipope.org" 
                );
my ($foo) = new Server(%config);

my ($allowed) = ['.*antipope\.org', 
                 '.*easynet\.co\.uk', 
		 '.*businessmonitor.co\.uk'];

my ($forbidden) = [ '194\.205\.10\.2'];

$foo->allowed($allowed);
$foo->forbidden($forbidden);
print "Server started\n";
$foo->run();


# ---- EXAMPLE #2 -- a psychotherapy server using Eliza -----------------

my ($cb) = sub {
    my ($tmp) = ""; 
    my ($el) = new Chatbot::Eliza;
    while (defined ($tmp = <STDIN>)) {
        # a little bit of harmless fun which demonstrates interactive
        # commands on a server
        #
        my ($p) = "";
        print STDOUT "Let me help you.\n=> ";
        while (defined($p = <STDIN>)) {
            if ($p =~ /^(bye|exit|quit|\.)/i) { 
                 return; 
            } ;
            chomp $p;
            print STDOUT $el->transform($p), "\n=> ";
        }
    }
};

# ---- EXAMPLE #3 -- a working SMTP server (TBC) -----------------

