# $Id: test.pl,v 1.11 2002/01/10 20:45:51 jkeroes Exp $
#
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use Test::More tests => 24;

use Term::ReadKey;

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
    skip("Won't login to router without a login and password.", 19)
	unless $LOGIN && $PASSWD;

    ok( $S = Net::Telnet::Cisco->new( Errmode	 => 'return',	
				      Host	 => $ROUTER,
				      Input_log  => $input_log,
				      Dump_log   => $dump_log,
				    ),  "new() object" );
    ok( $S->login(-Name     => $LOGIN,
		  -Password => $PASSWD,
		  -Passcode => $PASSCODE), "login()"		);
    ok( $S->print('terminal length 0'),	"print() (unset paging)");
    ok( $S->waitfor($S->prompt),	"waitfor() prompt"	);
    ok( $S->cmd('show clock'),		"cmd() short"		);
    ok( $S->cmd('show ver'),		"cmd() medium"		);
    ok( $S->cmd('show run'),		"cmd() long"		);

    # $seen should be incrememnted to 1.
    my $seen;
    ok( $S->errmode(sub {$seen++}), 	"set errmode(CODEREF)"	);
    $S->cmd(  "Small_Change_got_rained_on_with_his_own_thirty_eight"
	    . "_And_nobody_flinched_down_by_the_arcade");
    ok( $seen,				"error() called"	);

    # $seen should not have been incremented.
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
	&& $S->timed_out,		"waitfor() timeout" );

    ok ($S->cmd("show clock"),		"cmd() after waitfor()" );

    # log checks
    ok( -e $input_log, 			"input_log() created"	);
    ok( -e $dump_log, 			"dump_log() created"	);
}

# $S->errmode('die');
# $S->timeout(30);
# $S->always_waitfor_prompt(1);

SKIP: {
    skip("Won't enter enabled mode without an enable password", 3)
	unless $LOGIN && $PASSWD && $EN_PASS;
    ok( $S->disable,			"disable()"		);
    ok( $S->enable($EN_PASS),		"enable()"		);
    ok( $S->is_enabled,			"is_enabled()"		);
}

#------------------------------------------------------------
# subs
#------------------------------------------------------------

sub get_login {
    print <<EOB;

Net::Telnet::Cisco needs to log into a router to
perform it\'s full suite of tests. To log in, we
need a test router, a login, a password, an
optional enable password, and an optional
SecurID/TACACS PASSCODE.

To skip these tests, hit "return".

EOB
    print "\Router: " unless $ROUTER;
    $ROUTER ||= <STDIN>;
    chomp $ROUTER;
    return unless $ROUTER;

    print "Login: " unless $LOGIN;
    $LOGIN ||= <STDIN>;
    chomp $LOGIN;
    return unless $LOGIN;

    print "Passwd: " unless $PASSWD;

    if ( $Term::ReadKey::VERSION ) {
	ReadMode( 'noecho' );
	$PASSWD ||= ReadLine(0);
	chomp $PASSWD;
	ReadMode( 'normal' );
    } else {
	$PASSWD = <STDIN>;
	chomp $PASSWD;
    }
    print "\n";

    return unless $PASSWD;

    print "Enable Passwd [optional] : " unless $EN_PASS;

    if ( $Term::ReadKey::VERSION ) {
	ReadMode( 'noecho' );
	$EN_PASS ||= ReadLine(0);
	chomp $EN_PASS;
	ReadMode( 'normal' );
	print "\n";
    } else {
	$EN_PASS = <STDIN>;
	chomp $EN_PASS;
    }
    print "SecurID/TACACS PASSCODE [optional] : " unless $PASSCODE;
    $PASSCODE ||= <STDIN>;
    chomp $PASSCODE;
    print "\n";

}
