package Net::Telnet::Cisco;

#-----------------------------------------------------------------
#
# Net::Telnet::Cisco - interact with a Cisco router
#
# $Id: Cisco.pm,v 1.4 2000/07/30 22:16:51 jkeroes Exp $
#
# Todo: Add error and access logging.
#
# POD documentation at end of file.
#
#-----------------------------------------------------------------

use strict;
use Net::Telnet 3.02;
use AutoLoader;
use Carp;

use vars qw($AUTOLOAD @ISA $VERSION);

@ISA      = qw(Net::Telnet);
$VERSION  = '1.03';

#------------------------------
# New Methods
#------------------------------

# Tries to enter enabled mode with the password arg.
sub enable {
    my ($self, $en_pass) = @_;
#    return $self->error( "Can't enable without a password" )
#        unless defined $en_pass;

    # Store the old prompt without the //s around it.
    my ($old_prompt) = re_sans_delims($self->prompt);

    unless ( $self->is_enabled ) {
	# We need to expect either a Password prompt or a
	# typical prompt. If the user doesn't have enough
	# access to run the 'enable' command, the device
	# won't even query for a password, it will just
	# ignore the command and display another [boring] prompt.
	$self->cmd(String => 'enable',
		   Prompt => "/[Pp]assword[: ]*\$|$old_prompt/",
		  );

	if ( $self->last_prompt =~ /[Pp]ass/ ) {
	    if ( defined $en_pass ) {
		$self->cmd($en_pass);
	    } else {
		$self->cmd('');
	    }
	}
    }
    return $self->is_enabled ? 1 : $self->error('Failed to enter enabled mode');
}

# Leave enabled mode.
sub disable {
    my $self	= shift;
    $self->cmd('disable');
    return $self->is_enabled ? $self->error('Failed to exit enabled mode') : 1;
}

# Displays the last prompt.
sub last_prompt {
    my $self = shift;
    my $stream = $ {*$self}{net_telnet_cisco};
    exists $stream->{last_prompt} ? $stream->{last_prompt} : undef;
}


# Displays the last command.
sub last_cmd {
    my $self = shift;
    my $stream = $ {*$self}{net_telnet_cisco};
    exists $stream->{last_cmd} ? $stream->{last_cmd} : undef;
}

# Examines the last prompt to determine the current mode.
# 1     => enabled.
# undef => not enabled.
sub is_enabled { $_[0]->last_prompt =~ /\#|enable/ ? 1 : undef }

#------------------------------------------
# Overridden Methods
#------------------------------------------

sub new {
    my $class = shift;

    # There's a new cmd_prompt in town.
    my $self = $class->SUPER::new(
       	prompt => '/[\w().-]*[\$#>]\s?(?:\(enable\))?\s*$/',
	@_,			# user's additional arguments
    ) or return;

    *$self->{net_telnet_cisco} = {
	last_prompt => '',
        last_cmd    => '',
    };

    $self;
} # end sub new


# The new prompt() stores the last matched prompt for later
# fun 'n amusement. You can access this string via $self->last_prompt.
#
# It also parses out any router errors and stores them in the
# correct place, where they can be acccessed/handled by the
# Net::Telnet error methods.
#
# No POD docs for prompt(); these changes should be transparent to
# the end-user.
sub prompt {
    my( $self, $prompt ) = @_;
    my( $prev, $stream );

    $stream  = ${*$self}{net_telnet_cisco};
    $prev    = $self->SUPER::prompt;

    ## Parse args.
    if ( @_ == 2 ) {
        defined $prompt or $prompt = '';

        return $self->error('bad match operator: ',
                            "opening delimiter missing: $prompt")
            unless $prompt =~ m|^\s*/|;

	$self->SUPER::prompt($prompt);

    } elsif (@_ > 2) {
        return $self->error('usage: $obj->prompt($match_op)');
    }

    return $prev;
} # end sub prompt

# cmd() now parses errors and sticks 'em where they belong.
#
# This is a routerish error:
#   routereast#show asdf
#                     ^
#   % Invalid input detected at '^' marker.
#
# "show async" is valid, so the "d" of "asdf" raised an error.
#
# If an error message is found, the following error message
# is sent to Net::Telnet's error()-handler:
#
#   Last command and router error:
#   <last command prompt> <last command>
#   <error message fills remaining lines>

sub cmd {
    my $self             = shift;
    my $ok               = 1;
    my $cmd;

    # Extract the command from arguments
    if ( @_ == 1 ) {
	$cmd = $_[0];
    } elsif ( @_ >= 2 ) {
	my @args = @_;
	while ( my ( $k, $v ) = splice @args, 0, 2 ) {
	    $cmd = $v if $k =~ /^-?[Ss]tring$/;
	}
    }

    $ {*$self}{net_telnet_cisco}{last_cmd} = $cmd;

    my @output = $self->SUPER::cmd(@_);

    for ( my ($i, $lastline) = (0, '');
	  $i <= $#output;
	  $lastline = $output[$i++] ) {

	# This may have to be a pattern match instead.
	if ( ( substr $output[$i], 0, 1 ) eq '%' ) {

	    if ( $output[$i] =~ /'\^' marker/ ) { # Typo & bad arg errors
		chomp $lastline;
		$self->error( join "\n",
			             "Last command and router error: ",
			             ( $self->last_prompt . $cmd ),
			             $lastline,
			             $output[$i],
			    );
		splice @output, $i - 1, 3;

	    } else { # All other errors.
		chomp $output[$i];
		$self->error( join "\n",
			      "Last command and router error: ",
			      ( $self->last_prompt . $cmd ),
			      $output[$i],
			    );
		splice @output, $i, 2;
	    }

	    $ok = undef;
	    last;
	}
    }
    return wantarray ? @output : $ok;
}

# waitfor now stores prompts to $obj->last_prompt()
sub waitfor {
    my $self = shift;
    return unless @_;

    # $isa_prompt will be built into a regex that matches all currently
    # valid prompts.
    #
    # -Match args will be added to this regex. The current prompt will
    # be appended when all -Matches have been exhausted.
    my $isa_prompt;

    # Things that /may/ be prompt regexps.
    my $promptish = '^\s*(?:/|m\s*\W).*';


    # Parse the -Match => '/prompt \$' type options
    # waitfor can accept more than one -Match argument, so we can't just
    # hashify the args.
    if ( @_ >= 2 ) {
	my @args = @_;
	while ( my ( $k, $v ) = splice @args, 0, 2 ) {
	    if ( $k =~ /^-?[Mm]atch$/ && $v =~ /($promptish)/ ) {
		if ( my $addme = re_sans_delims($1) ) {
		    $isa_prompt .= $isa_prompt ? "|$addme" : $addme;
		} else {
		    return $self->error("Bad regexp '$1' passed to waitfor().");
		}
	    }
	}
    } elsif ( @_ == 1 ) {
	# A single argument is always a match.
	if ( $_[0] =~ /($promptish)/ and my $addme = re_sans_delims($1) ) {
	    $isa_prompt .= $isa_prompt ? "|$addme" : $addme;
	} else {
	    return $self->error("Bad regexp '$_[0]' passed to waitfor().");
	}
    }

    # Add the current prompt if it's not already there.
    if ( index($isa_prompt, $self->prompt) != -1
	 and my $addme = re_sans_delims($self->prompt) ) {
	$isa_prompt .= "|$addme";
    }

    # Call the real waitfor.
    my ( $prematch, $match ) = $self->SUPER::waitfor(@_);

    # If waitfor was, in fact, passed a prompt then find and store it.
    if ( $isa_prompt && defined $match ) {
	(${*$self}{net_telnet_cisco}{last_prompt})
	    = $match =~ /($isa_prompt)/;
    }
    return wantarray ? ( $prematch, $match ) : 1;
}


sub login {
    my($self) = @_;
    my(
       $cmd_prompt,
       $endtime,
       $error,
       $lastline,
       $match,
       $orig_errmode,
       $orig_timeout,
       $passwd,
       $prematch,
       $reset,
       $timeout,
       $usage,
       $username,
       %args,
       );
    local $_;

    ## Init vars.
    $timeout = $self->timeout;
    $self->timed_out('');
    return if $self->eof;
    $cmd_prompt = $self->prompt;
    $usage = 'usage: $obj->login(Name => $name, Password => $password, '
	   . '[Prompt => $match,] [Timeout => $secs,])';

    if (@_ == 3) {  # just username and passwd given
	($username, $passwd) = (@_[1,2]);
    }
    else {  # named args given
	## Get the named args.
	(undef, %args) = @_;

	## Parse the named args.
	foreach (keys %args) {
	    if (/^-?name$/i) {
		$username = $args{$_};
		defined($username)
		    or $username = "";
	    }
	    elsif (/^-?pass/i) {
		$passwd = $args{$_};
		defined($passwd)
		    or $passwd = "";
	    }
	    elsif (/^-?prompt$/i) {
		$cmd_prompt = $args{$_};
		defined $cmd_prompt
		    or $cmd_prompt = '';
		return $self->error("bad match operator: ",
				    "opening delimiter missing: $cmd_prompt")
		    unless ($cmd_prompt =~ m(^\s*/)
			    or $cmd_prompt =~ m(^\s*m\s*\W)
			   );
	    }
	    elsif (/^-?timeout$/i) {
		$timeout = _parse_timeout($args{$_});
	    }
	    else {
		return $self->error($usage);
	    }
	}
    }

    return $self->error($usage)
	unless defined($username) and defined($passwd);

    ## Override these user set-able values.
    $endtime = _endtime($timeout);
    $orig_timeout = $self->timeout($endtime);
    $orig_errmode = $self->errmode('return');

    ## Create a subroutine to reset to original values.
    $reset
	= sub {
	    $self->errmode($orig_errmode);
	    $self->timeout($orig_timeout);
	    1;
	};

    ## Create a subroutine to generate an error for user.
    $error
	= sub {
	    my($errmsg) = @_;

	    &$reset;
	    if ($self->timed_out) {
		return $self->error($errmsg);
	    }
	    elsif ($self->eof) {
		($lastline = $self->lastline) =~ s/\n+//;
		return $self->error($errmsg, ": ", $lastline);
	    }
	    else {
		return $self->error($self->errmsg);
	    }
	};

    ## Wait for login prompt.
    ($prematch, $match) = $self->waitfor(-match => '/[Ll]ogin[:\s]*$/',
					 -match => '/[Uu]sername[:\s]*$/',
					 -match => '/[Pp]assword[:\s]*$/')
	or do {
	    return &$error("read eof waiting for login or password prompt")
		if $self->eof;
	    return &$error("timed-out waiting for login or password prompt");
	};

    unless ( $match =~ /[Pp]ass/ ) {
	## Send login name.
	$self->print($username)
  	    or return &$error("login disconnected");

	## Wait for password prompt.
	$self->waitfor(-match => '/[Pp]assword[: ]*$/')
	    or do {
		return &$error("read eof waiting for password prompt")
		    if $self->eof;
		return &$error("timed-out waiting for password prompt");
	    };
    }
	
    ## Send password.
    $self->print($passwd)
        or return &$error("login disconnected");

    ## Wait for command prompt or another login prompt.
    ($prematch, $match) = $self->waitfor(-match => '/[Ll]ogin[:\s]*$/',
					 -match => '/[Uu]sername[:\s]*$/',
					 -match => '/[Pp]assword[:\s]*$/',
					 -match => $cmd_prompt)
	or do {
	    return &$error("read eof waiting for command prompt")
		if $self->eof;
	    return &$error("timed-out waiting for command prompt");
	};

    ## Reset object to orig values.
    &$reset;

    ## It's a bad login if we got another login prompt.
    return $self->error("login failed: access denied or bad name or password")
	if $match =~ /(?:[Ll]ogin|[Uu]sername|[Pp]assword)[: ]*$/;

    1;
} # end sub login

#------------------------------
# Class methods
#------------------------------

# Return a Net::Telnet regular expression without the delimiters.
sub re_sans_delims { ( $_[0] =~ m(^\s*m?\s*(\W)(.*)\1\s*$) )[1] }

# Look for subroutines in Net::Telnet if we can't find them here.
sub AUTOLOAD {
    my ($self) = @_;
    croak "$self is an [unexpected] object, aborting" if ref $self;
    $AUTOLOAD =~ s/.*::/Net::Telnet::/;
    goto &$AUTOLOAD;
}

=pod

=head1 NAME

Net::Telnet::Cisco - interact with a Cisco router

=head1 SYNOPSIS

  use Net::Telnet::Cisco;

  my $cs = Net::Telnet::Cisco->new( Host => '123.123.123.123' );
  $cs->login( 'login', 'password' );

  # Turn off paging
  my @cmd_output = $cs->cmd( 'terminal length 0' );

  # Execute a command
  @cmd_output = $cs->cmd( 'show running-config' );
  print @cmd_output;

  # Generate an error on purpose
  # This error handler prints the errmsg and continues.
  $cs->errmode( sub { print @_, "\n" } );

  @cmd_output = $cs->cmd( 'asdf' ); # Bad command.

  print "-" x 30, "\n";
  print "Last prompt: <",  $cs->last_prompt, ">\n";
  print "Last command: <", $cs->last_cmd,    ">\n";
  print "Last error: <",   $cs->errmsg,      ">\n";
  print "Cmd output: <",   @cmd_output,      ">\n";
  print "-" x 30, "\n";

  # Try out enable mode
  if ( $cs->enable("enable_password") ) {
      @cmd_output = $cs->cmd('show privilege');
      print "Cmd output: <", @cmd_output, ">\n";
  } else {
      warn "Can't enable: " . $cs->errmsg;
  }

  $cs->close;

=head1 DESCRIPTION

Net::Telnet::Cisco provides additional functionality to Net::Telnet
for dealing with Cisco routers.

Things you should know:

The default cmd_prompt is /[\w().-]*[\$#>]\s?(?:\(enable\))?\s*$/,
suitable for matching promtps like 'rtrname$ ', 'rtrname# ', and
'rtrname> (enable) '.

cmd() parses router-generated error messages - the kind that
begin with a '%' - and stows them in $obj->errmsg(), so that
errmode can be used to perform automatic error-handling actions.

=head1 FIRST

Before you use Net::Telnet::Cisco, you should probably have a good
understanding of Net::Telnet, so perldoc Net::Telnet first, and then
come back to Net::Telnet::Cisco to see where the improvements are.

Some things are easier to accomplish with Net::SNMP. SNMP has three
advantages: it's faster, handles errors better, and doesn't use any
vtys on the router. SNMP does have some limitations, so for anything
you can't accomplish with SNMP, there's Net::Telnet::Cisco.

=head1 METHODS

New methods not found in Net::Telnet follow:

=over 4

=item B<enable> - enter enabled mode

    $ok = $obj->enable;

    $ok = $obj->enable( $password );

This method changes privilege level to enabled mode, (i.e. root)

If an argument is provided by the caller, it will be used as
a password.

enable() returns 1 on success and undef on failure.

=item B<disable> - leave enabled mode

    $ok = $obj->disable;

This method exits the router's privileged mode.

=item B<last_prompt> - displays the last prompt matched by prompt()

    $match = $obj->last_prompt;

last_prompt() will return '' if the program has not yet matched a
prompt.

=item B<login> - login to a router.

    $ok = $obj->login($username, $password);

    $ok = $obj->login(Name     => $username,
                      Password => $password,
                      [Prompt  => $match,]
                      [Timeout => $secs,]);

Net::Telnet::Cisco will correctly log into a router if the session
begins with a password prompt (and ignores the login or username
step entirely).

=back

=head1 AUTHOR

Joshua_Keroes@eli.net $Date: 2000/07/30 22:16:51 $

It would greatly amuse the author if you would send email to him
and tell him how you are using Net::Telnet::Cisco.

=head1 SEE ALSO

Net::Telnet, Net::SNMP

=head1 COPYRIGHT

Copyright (c) 2000 Joshua Keroes, Electric Lightwave Inc.
All rights reserved. This program is free software; you
can redistribute it and/or modify it under the same terms
as Perl itself.

=cut

1;

__END__
