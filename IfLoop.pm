package IfLoop;

use 5.006;
use strict;
use warnings;

use Filter::Util::Call;
use Text::Balanced;

#require Exporter;
#our @ISA = qw(Exporter);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use IfLoop ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
#our %EXPORT_TAGS = ( 'all' => [ qw( ) ] );
#our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
#our @EXPORT = qw();

our $VERSION = '0.02';
our $DEBUG   = 0;

# Helps tell us about where in the file we are.
my $offset;

#---------------------------------------------------------------------------
#---------------------------------------------------------------------------
sub line
{
    my ($pretext,$offset) = @_;
    ($pretext=~tr/\n/\n/)+($offset||0);
}

#---------------------------------------------------------------------------
#---------------------------------------------------------------------------
sub import
{
    my($type, @arguments) = @_ ;

    if(scalar(@arguments) == 0)
    {
	@arguments = qw(while until);
    }
    
    my $tmp = join ':1:', @arguments,':1';
    @arguments = split ':', $tmp;

    $offset = (caller)[2]+1;
    filter_add({@arguments}) ;
}

#---------------------------------------------------------------------------
#---------------------------------------------------------------------------
sub unimport
{	
    filter_del();
}

#---------------------------------------------------------------------------
#---------------------------------------------------------------------------
sub handle_filehandles
{
    my $bool_condition = shift;
    my $r_source       = shift;
    my $line           = shift;

    my @pos = Text::Balanced::_match_codeblock(\$bool_condition,
					       qr/\s*/,
					       qr/\(/,qr/\)/,
					       qr/[(<]/,qr/[>)]/,
					       undef);
    if(@pos)
    {
	my $tmp = substr($bool_condition,$pos[0],$pos[4]-$pos[0]);
	if($tmp =~ m/(<.*>)/)
	{
	    my $file_access = $`.$1;
	    if($file_access !~ m/\$\_\s*=\s*<.*>/o)
	    {
		die "Filehandles \"<FILE>\" must be used like \"\$_ = <FILE>\"\n".
		    "Like the normal \"if-elsif-else\" syntax. \$_ is not set automagically!\n".
		    "Check bool statement: $bool_condition part of chain near line# ".
		    &line(substr($$r_source,0,pos $$r_source),$line)."\n";
	    }
	}
    }
}

#---------------------------------------------------------------------------
#---------------------------------------------------------------------------
sub filter
{
    my $self = shift ;
    my $status;
    
    $status = filter_read(100_000);
    return $status if($status < 0);

    $_ = &filter_blocks($self,$_,$offset);

    $status ;
}

#---------------------------------------------------------------------------
#---------------------------------------------------------------------------
sub filter_blocks
{
    #Many a regex shamelessly stolen from Damian's Switch module.

    my $self   = shift;
    my $source = shift;
    my $line   = shift;

    my $keyword = '';

    while($source =~ m/(\n*)(\s*)(elsifwhile)\b(?=\s*[(])(?{$keyword = $3})/gc ||
          $source =~ m/(\n*)(\s*)(ifwhile)\b(?=\s*[(])(?{$keyword = $3})/gc    ||
          $source =~ m/(\n*)(\s*)(elsifuntil)\b(?=\s*[(])(?{$keyword = $3})/gc ||
          $source =~ m/(\n*)(\s*)(ifuntil)\b(?=\s*[(])(?{$keyword = $3})/gc )
    {
	my $r_fctn;
	my %args = (self     => $self,
		    r_source => \$source,
		    line     => $line,
		    keyword  => $keyword);

	$keyword =~ m/(?:if|elsif)(.*)/;
	{
	    no strict 'refs';
	    my $base_keyword = $1;

	    next if(!$self->{$base_keyword});
	    $r_fctn = \&{${base_keyword}.'_key'};
	}

	$r_fctn->(\%args) if(ref($r_fctn) eq 'CODE');	
    }
    print STDERR $source if($DEBUG);
    return $source;
}

#---------------------------------------------------------------------------
#---------------------------------------------------------------------------
{ no warnings;  *while_key = *until_key = \&while_until_key; }

sub while_until_key
{
    my $r_args   = shift; 
    my $self     = $r_args->{self};
    my $r_source = $r_args->{r_source};
    my $line     = $r_args->{line};
    my $keyword  = $r_args->{keyword}; 
    
    
    my @pos = Text::Balanced::_match_codeblock($r_source,
					       qr/\s*/,
					       qr/\(/,qr/\)/,
					       qr/[{(]/,qr/[)}]/,
					       undef);
    
    print STDERR "|@pos|"                                              if($DEBUG);
    print STDERR substr($$r_source,$pos[0]-10,$pos[4]-$pos[0]+10),"\n" if($DEBUG);
    
    #substr($source,$pos[0]-10,$pos[4]-$pos[0]+10) #grabs elsewhile(...);
    #substr($source,$pos[0],$pos[4]-$pos[0])       #grabs (...);
    
    my $bool_condition = substr($$r_source,$pos[0],$pos[4]-$pos[0]);
    my @replace=($pos[0]-7);
    my $text = 'if';
    
    if($keyword =~ m/elsif.*/)
    {
	$text  = "elsif";
	$replace[0] = $pos[0]-10; #It just so happens that until and while
	#both have five letters in them.
    }
    
    #Filehandles that set $_ are speeeeecial Mmm-Kay
    # lets die and warn the user with some position information.
    &handle_filehandles($bool_condition,$r_source,$line);
    
    #Adjust the syntax of the if to account for until. HA!
    if($keyword =~ m/.*until/){$text .= "(!$bool_condition)\{do";}
    else                      {$text .= "$bool_condition\{do";   }
    
    @pos = Text::Balanced::_match_codeblock($r_source,
					    qr/\s*/,
					    qr/\{/,qr/\}/,
					    qr/\{/,qr/\}/,
					    undef);
    print STDERR "|@pos|"                                          if($DEBUG);
    print STDERR substr($$r_source,$pos[0],$pos[4]-$pos[0]),"\n"   if($DEBUG);
    
    #Check to make sure the syntax is "if*(){code}" not "code if*();" 
    if(scalar @pos)
    {
	my $inner = substr($$r_source,$pos[0],$pos[4]-$pos[0]);
	
	push @replace, ($pos[4]-$pos[0])+$pos[0];
	
	#Allow N number of nests for the syntax.
	$inner = &filter_blocks($self,$inner,$line);
	
	#Adjust the syntax of the if to account for until. HA!
	if($keyword =~ m/.*until/)
	{
	    $text .= $inner."until$bool_condition}";
	}
	else
	{
	    $text .= $inner."while$bool_condition}";
	}
	
	print STDERR "|@replace|" if($DEBUG);
	
	substr($$r_source,$replace[0],$replace[1]-$replace[0],$text);
    }
    elsif($keyword =~ m/if.*/) #It is one of those backward things!
    {
	die "Cannot use \"$&\" in one-liner if. Use $&(...){} intead.\n";
    }
    else
    {
	die "Parse Error. LALALALALA... go away, go away!\n\n".
            "If you're seeing this it means the module has a bug.\n".
            "Please contact the author with the code that caused this error.\n".
	    "Thank you.\n";
    }
}# End fctn while_until_key;


1;
__END__

=head1 NAME

IfLoop - Perl extension for the if-elsif-else syntax in Perl.

=head1 SYNOPSIS

  use IfLoop qw( while until );

=head1 DESCRIPTION

IfLoop allows for the creation of if-elsif-else chains that contain loop structures in the if-elsif-else syntax. Just like if-elsif-else chains if-elsifwhile-elsifuntil-else chains can be of arbitrary length and can be nested. Any ifwhile, elsifwhile, etc. syntax can be intermingled with the normal if-elsif-else chains to create combination chains. (See B<EXAMPLES>) 

=head1 EXAMPLES

 #Use all extensions
 use IfLoop;


 # Only use the ifwhile/elseifwhile extension.
 use IfLoop qw( while );

 ifwhile(A)
 {
     #code...
 }
 else
 {
     #code...
 }

 # Use both the ifuntil/elseifuntil and ifwhile/elsifwhile extensions.
 use IfLoop qw( until while );

 if(A)
 {
     #code...
 }
 elsifuntil(B)
 {
     #code...
 }
 elsifuntil(C)
 {
     #code...
 }
 else
 {
     #code...
 }

=head1 LITERAL TRANSLATION

IfLoop actaully just translates its extended syntax into normal Perl syntax. Here are the translations.

 ifwhile(A)
 {
     #code...
 }

translates to:

 if(A)
 {
     do
     {
 	#code
     }while(A)
 }

 ifuntil(A)
 {
     #code...
 }

translates to:

 if(!(A))
 {
     do
     {
 	#code
     }until(A)
 }

Translation of elsif statments occurs in the same way.

=head1 TODO

=over 2

=item 
Add the B<for> and B<foreach> syntax.

=item
For completeness, make the B<code ifwhile(A);> syntax work.

=back

=head1 BUGS

None known

=head1 AUTHOR

Brandon Willis, brandon@silverorb.net

=head1 THANKS

IfLoop's implementation was heavily inspired by Damian Conway's Switch.pm. 

=cut

=head1 COPYRIGHT AND LICENCE

Copyright (c) 2003, Brandon Willis. All Rights Reserved.
This module is free software. It may be used, redistributed
and/or modified under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>.

=head1 HISTORY

=over 8

=item 0.02

Initial Release 

=back

