#!/usr/bin/perl

$rc = system("$^X testguts.pl");
if ($rc == 15) {
    print "ok 6\n"; # the quit() method worked -- exit via signal 15
} else {
    print "not ok 6: $rc\n";
}
  

exit;
