# $Id: test.pl,v 1.19 2002/04/02 18:59:30 jkeroes Exp $
#
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use Test::More tests => 32;
#use Test::More qw/no_plan/;
use Carp;
use Cwd;

use vars qw/$ROUTER $PASSWD $LOGIN $S $EN_PASS $PASSCODE/;

my $input_log = "input.log";
my $dump_log  = "dump.log";

#------------------------------------------------------------
# tests
#------------------------------------------------------------

get_login();

BEGIN { use_ok("Net::Telnet::Cisco") }

ok($Net::Telnet::Cisco::VERSION, 	"\$VERSION set");

SKIP: {
    skip("Won't login to router without a login and password.", 27)
	unless $LOGIN && $PASSWD;

    ok( $S = Net::Telnet::Cisco->new( Errmode	 => \&fail,
				      Host	 => $ROUTER,
				      Input_log  => $input_log,
				      Dump_log   => $dump_log,
				    ),  "new() object" );

    $S->errmode(sub {&confess});

    # So we pass an even number of args to login()
    $LOGIN	   ||= '';
    $PASSWD	   ||= '';
    $PASSCODE      ||= '';

    ok( $S->login(-Name     => $LOGIN,
		  -Password => $PASSWD,
		  -Passcode => $PASSCODE), "login()"		);

    # Autopaging tests
    ok( $S->autopage,			"autopage() on"		);
    my @out = $S->cmd('show ver');
    ok( $out[-1] !~ /--More--/, 	"autopage() last line"	);
    ok( $S->last_prompt !~ /--More--/,	"autopage() last prompt" );

    open LOG, "< $input_log" or die "Can't open log: $!";
    my $log = join "", <LOG>;
    close LOG;

    # Remove last prompt, which isn't present in @out
    $log =~ s/\cJ\cJ.*\Z//m;

    # get rid of "show ver" line
    shift @out;

    # Strip ^Hs from log
    $log = Net::Telnet::Cisco::_normalize($log);

    my $out = join "", @out;
    $out =~ s/\cJ\cJ.*\Z//m;

    my $i = index $log, $out;
    ok( $i + length $out == length $log, "autopage() 1.09 bugfix" );

    # Turn off autopaging. We should timeout with a More prompt
    # on the last line.
    ok( $S->autopage(0) == 0,		"autopage() off"	);

    $S->errmode('return');	# Turn off error handling.
    $S->errmsg('');		# We *want* this to timeout.

    $S->cmd(-String => 'show run', -Timeout => 5);
    ok( $S->errmsg =~ /timed-out/,	"autopage() not called" );

    $S->errmode(\&fail);	# Restore error handling.
    $S->cmd("\cZ");		# Cancel out of the "show run"

    # Print variants
    ok( $S->print('terminal length 0'),	"print() (unset paging)");
    ok( $S->waitfor($S->prompt),	"waitfor() prompt"	);
    ok( $S->cmd('show clock'),		"cmd() short"		);
    ok( $S->cmd('show ver'),		"cmd() medium"		);
    ok( @confg = $S->cmd('show run'),	"cmd() long"		);

    # breaks
SKIP: {
    skip("ios_break test unreliable", 1);
    $old_timeout = $S->timeout;
    $S->timeout(1);
    $S->errmode(sub { $S->ios_break });
    @break_confg = $S->cmd('show run');
    $S->timeout($old_timeout);
    ok( @break_confg < @confg,		"ios_break()"		);
}

    # Error handling
    my $seen;
    ok( $S->errmode(sub {$seen++}), 	"set errmode(CODEREF)"	);
    $S->cmd(  "Small_Change_got_rained_on_with_his_own_thirty_eight"
	    . "_And_nobody_flinched_down_by_the_arcade");

    # $seen should be incrememnted to 1.
    ok( $seen,				"error() called"	);

    # $seen should not be incremented (it should remain 1)
    ok( $S->errmode('return'),		"no errmode()"		);
    $S->cmd(  "Brother_my_cup_is_empty_"
	    . "And_I_havent_got_a_penny_"
	    . "For_to_buy_no_more_whiskey_"
	    . "I_have_to_go_home");
    ok( $seen == 1,			"don't call error()" );

    ok( $S->always_waitfor_prompt(1),	"always_waitfor_prompt()" );
    ok( $S->print("show clock")
	&& $S->waitfor("/not_a_real_prompt/"),
					"waitfor() autochecks for prompt()" );
    ok( $S->always_waitfor_prompt(0) == 0, "don't always_waitfor_prompt()" );
    ok( $S->timeout(5),			"set timeout to 5 seconds" );
    ok( $S->print("show clock")
	&& $S->waitfor("/not_a_real_prompt/")
	&& $S->timed_out,		"waitfor() timeout" 	);

    # restore errmode to test default.
    $S->errmode(sub {&fail});
    ok( $S->cmd("show clock"),		"cmd() after waitfor()" );

    # log checks
    ok( -e $input_log, 			"input_log() created"	);
    ok( -e $dump_log, 			"dump_log() created"	);

    $S = Net::Telnet::Cisco->new( Prompt => "/broken_pre1.08/" 	);
    ok( $S->prompt eq "/broken_pre1.08/", "new(args) 1.08 bugfix" );
}

SKIP: {
    skip("Won't enter enabled mode without an enable password", 3)
	unless $LOGIN && $PASSWD && $EN_PASS;
    ok( $S->disable,			"disable()"		);
    ok( $S->enable($EN_PASS),		"enable()"		);
    ok( $S->is_enabled,			"is_enabled()"		);
}

END { cleanup() };

#------------------------------------------------------------
# subs
#------------------------------------------------------------

sub cleanup {
    return unless -f "input.log" || -f "dump.log";
    my $dir = cwd();

    my $ans = "y";
    if ($ans eq "y") {
	print "Deleting logs in $dir...";
	unlink "input.log" or warn "Can't delete input.log! $!";
	unlink "dump.log"  or warn "Can't delete dump.log! $!";
	print "done.\n";
    } else {
	warn "Not deleting logs in $dir.\n";
    }
}

sub maskpass {
    return 'not set' unless defined $_[0];
    return ( '*' x ( length $_[0] ) ) . ' [masked]';
}

sub get_login {
    $ROUTER = $ENV{CISCO_TEST_ROUTER}   or return;
    $LOGIN  = $ENV{CISCO_TEST_LOGIN}    or return;
    $PASSWD = $ENV{CISCO_TEST_PASSWORD} or return;
    $EN_PASS  = $ENV{CISCO_TEST_ENABLE_PASSWORD};
    $PASSCODE = $ENV{CISCO_TEST_PASSCODE};

    printf STDERR
      <<EOB, $ROUTER, $LOGIN, maskpass($PASSWD), maskpass($EN_PASS), maskpass($PASSCODE);
Using the following configuration for testing:
                    Router: %s
                     Login: %s
                  Password: %s
           Enable Password: %s
  SecureID/TACACS PASSCODE: %s

EOB
}
