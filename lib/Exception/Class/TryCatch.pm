package Exception::Class::TryCatch;

$VERSION     = "1.10";
@ISA         = qw (Exporter);
@EXPORT      = qw ( catch try );
@EXPORT_OK   = qw ( caught );

use 5.005; # Aiming for same as Exception::Class
#use warnings -- not supported in Perl 5.5, darn
use strict;
use Exception::Class;
use Exporter ();

my @error_stack;

##### main pod documentation #####

=head1 NAME

Exception::Class::TryCatch - Syntactic try/catch sugar for use with Exception::Class

=head1 SYNOPSIS

    use Exception::Class::TryCatch;
    
    # simple usage of catch()
    
    eval { Exception::Class::Base->throw('error') };
    catch my $err and warn $err->error;

    # catching only certain types or else rethrowing
    
    eval { Exception::Class::Base::SubClass->throw('error') };
    catch( my $err, ['Exception::Class::Base', 'Other::Exception'] )
        and warn $err->error; 
    
    # catching and handling different types of errors
    
    eval { Exception::Class::Base->throw('error') };
    if ( catch my $err ) {
        $err->isa('this') and do { handle_this($err) };
        $err->isa('that') and do { handle_that($err) };
    }
    
    # use "try eval" to push exceptions onto a stack to catch later
    
    try eval { 
        Exception::Class::Base->throw('error') 
    };
    do {
        # cleanup that might use "try/catch" again
    };
    catch my $err; # catches a matching "try"
  
=head1 DESCRIPTION

Exception::Class::TryCatch provides syntactic sugar for use with
L<Exception::Class> using the familiar keywords C<try> and C<catch>.  Its
primary objective is to allow users to avoid dealing directly with C<$@> by
ensuring that any exceptions caught in an C<eval> are captured as
L<Exception::Class> objects, whether they were thrown objects to begin with or
whether the error resulted from C<die>.  This means that users may immediately
use C<isa> and various L<Exception::Class> methods to process the exception. 

In addition, this module provides for a method to push errors onto a hidden
error stack immediately after an C<eval> so that cleanup code or other error
handling may also call C<eval> without the original error in C<$@> being lost.

Inspiration for this module is due in part to Dave Rolsky's
article "Exception Handling in Perl With Exception::Class" in
I<The Perl Journal> (Rolsky 2004).

The C<try/catch> syntax used in this module does not use code reference
prototypes the way the L<Error.pm|Error> module does, but simply provides some
helpful functionality when used in combination with C<eval>.  As a result, it
avoids the complexity and dangers involving nested closures and memory leaks
inherent in L<Error.pm|Error> (Perrin 2003).  

Rolsky (2004) notes that these memory leaks may not occur in recent versions of
Perl, but the approach used in Exception::Class::TryCatch should be safe for all
versions of Perl as it leaves all code execution to the C<eval> in the current
scope, avoiding closures altogether.

=head1 USAGE

=cut

#--------------------------------------------------------------------------#
# catch()
#--------------------------------------------------------------------------#

=head2 C<catch>

    # zero argument form
    my $err = catch;

    # one argument forms
    catch my $err;
    my $err = catch( [ 'Exception::Type', 'Exception::Other::Type' ] );

    # two argument form
    catch my $err, [ 'Exception::Type', 'Exception::Other::Type' ];

Returns an C<Exception::Class::Base> object (or an object which is a 
subclass of it) if an exception has been caught by C<eval> or else 
returns C<undef> if no error exists.  The exception is either popped
from a hidden error stack (see C<try>) or, if the stack is empty, taken from
the current value of C<$@>.

If the exception is not an C<Exception::Class::Base> object (or subclass
object), an C<Exception::Class::Base> object will be created using the string
contents of the exception.  This means that calls to C<die> will be wrapped and
may be treated as exception objects.  Other objects caught will be stringfied
and wrapped likewise.  Such wrapping will likely result in confusing stack
traces and the like, so any methods other than C<error> used on 
C<Exception::Class::Base> objects caught should be used with caution.

C<catch> is prototyped to take up to two optional scalar arguments.  The single
argument form has two variations.  

=over

=item *

If the argument is a reference to an array,
any exception caught that is not of the same type (or a subtype) of one
of the classes listed in the array will be rethrown.  

=item *

If the argument is not a reference to an array, C<catch> 
will set the argument to the same value that is returned. 
This allows for the C<catch my $err> idiom without parentheses.

=back

In the two-argument form, the first argument is set to the same value as is
returned.  The second argument must be an array reference and is handled 
the same as as for the single argument version with an array reference, as
given above.

=head2 C<caught> (DEPRECATED)

C<caught> is a synonym for C<catch> for syntactic convenience.

NOTE: Exception::Class version 1.21 added a "caught" method of its own.  It
provides somewhat similar functionality to this subroutine, but with very
different semantics.  As this class is intended to work closely with
Exception::Class, the existence of a subroutine and a method with the same name
is liable to cause confusion and this method is deprecated and may be removed
in future releases of Exception::Class::TryCatch.

This method is no longer exported by default.

=cut

sub catch(;$$) {
    my $e;
    my $err = @error_stack ? pop @error_stack : $@;
    if ($err eq '') {
        $e = undef;
    }
    elsif ( UNIVERSAL::isa($err, 'Exception::Class::Base' ) ) {
        $e = $err;
    } 
    else {
        # use error message or hope something stringifies
        $e = Exception::Class::Base->new( "$err" );
    }
    unless ( ref($_[0]) eq 'ARRAY' ) { 
        $_[0] = $e;
        shift;
    }
    if ($e) {
        if ( defined($_[0]) and ref($_[0]) eq 'ARRAY' ) {
            $e->rethrow() unless grep { $e->isa($_) } @{$_[0]};
        }
    }
    return $e;
}

*caught = \&catch;

#--------------------------------------------------------------------------#
# try()
#--------------------------------------------------------------------------#

=head2 C<try>

    # void context
    try eval {
      # dangerous code
    };
    do {
      # cleanup code can use try/catch
    };
    catch my $err;
 
    # scalar context
    $rv = try eval { return $scalar };

    # list context
    @rv = try [ eval { return @array } ];

Pushes the current error (C<$@>) onto a hidden error stack for later use by
C<catch>.  C<try> uses a prototype that expects a single scalar so that it can
be used with eval without parentheses.  As C<eval { BLOCK }> is an argument
to try, it will be evaluated just prior to C<try>, ensuring that C<try>
captures the correct error status.  C<try> does not itself handle any errors --
it merely records the results of C<eval>. C<try { BLOCK }> will be interpreted
as passing a hash reference and will (probably) not compile. (And if it does,
it will result in very unexpected behavior.)

Since C<try> requires a single argument, C<eval> will normally be called
in scalar context.  To use C<eval> in list context with C<try>, put the 
call to C<eval> in an anonymous array:  

  @rv = try [ eval {return @array} ];

When C<try> is called in list context, if the argument to C<try> is an array
reference, C<try> will dereference the array and return the resulting list.

In scalar context, C<try> passes through the scalar value returned
by C<eval> without modifications -- even if that is an array reference.

  $rv = try eval { return $scalar };
  $rv = try eval { return [ qw( anonymous array ) ] };

Of course, if the eval throws an exception, C<eval> and thus C<try> will return
undef.

C<try> must always be properly bracketed with a matching C<catch> or unexpected
behavior may result when C<catch> pops the error off of the stack.  C<try> 
executes right after its C<eval>, so inconsistent usage of C<try> like the
following will work as expected:

    try eval {
        eval { die "inner" };
        catch my $inner_err
        die "outer" if $inner_err;
    };
    catch my $outer_err;
    # handle $outer_err;
    
However, the following code is a problem:

    # BAD EXAMPLE
    try eval {
        try eval { die "inner" };
        die $@ if $@;
    };
    catch my $outer_err;
    # handle $outer_err;
    
This code will appear to run correctly, but C<catch> gets the exception
from the inner C<try>, not the outer one, and there will still be an exception
on the error stack which will be caught by the next C<catch> in the program, 
causing unexpected (and likely hard to track) behavior.

In short, if you use C<try>, you must have a matching C<catch>.  The problem
code above should be rewritten as:

    try eval {
        try eval { die "inner" };
        catch my $inner_err;
        $inner_err->rethrow if $inner_err;
    };
    catch my $outer_err;
    # handle $outer_err;

=cut

sub try($) {
    my $v = shift;
    push @error_stack, $@;
    return ref($v) eq 'ARRAY' ? @$v : $v if wantarray;
    return $v;
}


1; #this line is important and will help the module return a true value
__END__

=head1 REFERENCES

=over

=item 1. 

perrin. (2003), "Re: Re2: Learning how to use the Error module by example",
(perlmonks.org), Available: http://www.perlmonks.org/index.pl?node_id=278900
(Accessed September 8, 2004).

=item 2.

Rolsky, D. (2004), "Exception Handling in Perl with Exception::Class",
I<The Perl Journal>, vol. 8, no. 7, pp. 9-13

=back

=head1 SEE ALSO

- L<Exception::Class>

- L<Error> [but see (Perrin 2003) before using]

=head1 BUGS

Please report any bugs or feature using the CPAN Request Tracker.  
Bugs can be submitted by email to C<bug-DISTNAME@rt.cpan.org> or 
through the web interface at 
L<http://rt.cpan.org/Public/Dist/Display.html?Name=DISTNAME>

When submitting a bug or request, please include a test-file or a patch to an
existing test-file that illustrates the bug or desired feature.

=head1 AUTHOR

David A Golden 

dagolden@cpan.org

http://dagolden.com/

=head1 COPYRIGHT

Copyright (c) 2004, 2005, 2006 by David A. Golden

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=cut
