package Validate::JSONPath;

use strict;
use Data::Dumper;
use fields qw(pos jsonpath jlen);

my $DOC_CONTEXT = '$';
my $EVAL_CONTEXT = '@';

my $OPEN_SQUARE_BRACKET = '[';
my $CLOSE_SQUARE_BRACKET = ']';
my $OPEN_PARENTHESIS = '(';
my $CLOSE_PARENTHESIS = ')';
my $OPEN_BRACE = '{';
my $CLOSE_BRACE = '}';

my $WILDCARD = '*';
my $PERIOD = '.';
my $SPACE = ' ';
my $TAB = '\t';
my $CR = '\r';
my $LF = '\n';
my $BEGIN_FILTER = '?';
my $COMMA = ',';
my $SPLIT = ':';
my $MINUS = '-';
my $SINGLE_QUOTE = "\'";
my $DOUBLE_QUOTE = '"';
my $REGEX = "/";

sub new {
    my Validate::JSONPath $self = shift;
    my $jsonpath = shift;

    unless ( ref($self) ) {
        $self = fields::new($self);
        $self->{'jsonpath'} = $jsonpath;
        $self->{'jlen'} = length($jsonpath);
        $self->{'pos'} = 0;
    }
    return $self;
}

sub char_at {
    my Validate::JSONPath $self = shift;
    my $pos = shift // $self->{'pos'};
    my $val = substr($self->{'jsonpath'}, $pos, 1);
    return $val;
}

# int expressionEndIndex = path.nextIndexOf(expressionBeginIndex, CLOSE_SQUARE_BRACKET);
sub next_index_of {
    my Validate::JSONPath $self = shift;
    my $tgt = shift;
    my $pos = shift // $self->{'pos'};

    die("Invalid position: $pos") if ( $pos !~ /^[0-9]+$/ );

    my $read_pos = $pos;
    while ( $self->is_in_bounds($read_pos) ) {
        return $read_pos if ( $self->char_at($read_pos) eq $tgt );
        $read_pos++;
    }
    return -1;
}

sub index_of_next_significant {
    my Validate::JSONPath $self = shift;
    my $tgt = shift;
    my $pos = shift // $self->{'pos'};
    $pos++;
    #print "  pos = $pos!\n";
    while ( $self->is_in_bounds()
        and substr($self->{'jsonpath'}, $pos, 1) eq $SPACE
    ) {
        $pos++;
    }
    my $val = substr($self->{'jsonpath'}, $pos, 1);
    #print "  pos(2) = $pos! val = $val\n";
    if ( $val eq $tgt ) {
        return $pos;
    } else {
        return -1;
    }
}

sub next_significant_char {
    my Validate::JSONPath $self = shift;
    my $start_pos = shift // $self->{'pos'};
    my $read_pos = $start_pos + 1;
    while (
        $self->is_in_bounds($read_pos) and
        $self->char_at($read_pos) eq $SPACE
    ) {
        #print "! inc: $read_pos : $self->{'pos'} < $self->{'jlen'}\n";
        $read_pos++;
    }
    if ( $self->is_in_bounds($read_pos) ) {
        return $self->char_at($read_pos);
    } else {
        return ' ';
    }
}

sub next_significant_char_is {
    my Validate::JSONPath $self = shift;
    my $char = shift;
    my $start_pos = shift // $self->{'pos'};
    my $read_pos = $start_pos + 1;

    while (
        $self->is_in_bounds($read_pos)
        and $self->char_at($read_pos) eq $SPACE
    ) {
        $read_pos++;
    }
    #print "IS IN BOUNDS: " . $self->is_in_bounds($read_pos) . "\n";
    #print "char_at: " . $self->char_at($read_pos) . " == $char\n";

    return $self->is_in_bounds($read_pos)
        && $self->char_at($read_pos) eq $char;
}

sub next_index_of_unescaped {
    my Validate::JSONPath $self = shift;
    my ( $start_pos, $cc ) = @_;
    my $read_pos = $start_pos + 1;
    my $in_escape = 0;
    while ( $self->is_in_bounds($read_pos) ) {
        if ( $in_escape ) {
            $in_escape = 0;
        } elsif ( "\\" eq $self->char_at($read_pos) ) {
            $in_escape = 1;
        } elsif ( $cc eq $self->char_at($read_pos) and ! $in_escape ) {
            return $read_pos;
        }
        $read_pos++;
    }
    return -1;
}

sub read_whitespace {
    my Validate::JSONPath $self = shift;
    while ( $self->is_in_bounds() ) {
        if ( substr($self->{'jsonpath'}, $self->{'pos'}, 1) =~ /[\s\t\r\n]/ ) {
            $self->{'pos'}++;
        } else {
            last;
        }
    }
}

sub is_in_bounds {
    my Validate::JSONPath $self = shift;
    my $pos = shift // $self->{'pos'};
    return ( $pos < $self->{'jlen'} );
}

sub is_digit {
    my $val = shift;
    return $val =~ /^[0-9]$/;
}

sub index_of_closing {
    my Validate::JSONPath $self = shift;
    my ( $start_pos, $open_char, $close_char, $skip_strings, $skip_regex ) = @_;

    if ( $self->char_at($start_pos) ne $open_char ) {
        die("Expected $open_char but found " . $self->char_at($start_pos));
    }
    my $opened = 1;
    my $read_pos = $start_pos + 1;

    while ( $self->is_in_bounds($read_pos) ) {
        if ( $skip_strings ) {
            my $quote_chr = $self->char_at($read_pos);
            if ( $quote_chr eq $SINGLE_QUOTE || $quote_chr eq $DOUBLE_QUOTE ) {
                $read_pos = $self->next_index_of_unescaped($read_pos, $quote_chr);
            }
        }
        if ( $skip_regex ) {
            if ( $self->char_at($read_pos) eq $REGEX ) {
                $read_pos = $self->next_index_of_unescaped($read_pos, $REGEX);
                if ( $read_pos == -1 ) {
                    die("Could not find matching close for $REGEX when " .
                        "parsing regex in $self->{'jsonpath'}"
                    );
                }
                $read_pos++;
            }
        }
        $opened++ if ( $self->char_at($read_pos) eq $open_char );
        if ( $self->char_at($read_pos) eq $close_char ) {
            $opened--;
            return $read_pos if ( $opened == 0 );
        }
        $read_pos++;
    }
    return -1;
}

#########################
#########################
#########################

sub verify {
    my Validate::JSONPath $self = shift;
    $self->verify_context();
    $self->parse_path();
    return 1;
}

sub verify_context {
    my Validate::JSONPath $self = shift;
    my $first_char = substr($self->{'jsonpath'}, 0, 1);
    unless ( $first_char eq $DOC_CONTEXT or $first_char eq $EVAL_CONTEXT ) {
        die("Invalid $self->{'jsonpath'} pos[0] != $DOC_CONTEXT|$EVAL_CONTEXT");
    }
    my $last_char = substr($self->{'jsonpath'}, -1, 1);
    if ( $last_char eq '.' ) {
        die("Invalid $self->{'jsonpath'} cannot end with '.' ($last_char)");
    }
    $self->{'pos'}++;

    if ( ! $self->current_char_is($PERIOD)
        and ! $self->current_char_is($OPEN_SQUARE_BRACKET)
    ) {
        die("Illegal character at position $self->{'pos'} expected '.' or '['");
    }

    return;
}

sub parse_path {
    my Validate::JSONPath $self = shift;
    $self->read_whitespace();
    $self->read_next_token();
    return;
}

sub read_next_token {
    my Validate::JSONPath $self = shift;
    my $current = substr($self->{'jsonpath'}, $self->{'pos'}, 1);
    #print "rnt: pos=$self->{'pos'} current=$current\n";
    if ( $current eq $OPEN_SQUARE_BRACKET ) {
        return $self->read_bracket_property_token() ||
            $self->read_array_token() ||
            $self->read_wild_card_token() ||
            $self->read_filter_token() ||
            $self->read_placeholder_token() ||
            die("Could not parse token starting at position $self->{'pos'}" .
                " Expected ?, ', 0-9, * ");

    } elsif ( $current eq $PERIOD ) {
        #print "hello dot\n";
        return $self->read_dot_token() ||
            die("Could not parse token starting at position $self->{'pos'}");

    } elsif ( $current eq $WILDCARD ) {
        #print "hello wild\n";
        return $self->read_wild_card_token() ||
            die("Could not parse token starting at position $self->{'pos'}");
    } else {
        #print "hello prop\n";
        return $self->read_property_or_function_token() ||
            die("Could not parse token starting at position $self->{'pos'}");
    }
}

sub current_char {
    my Validate::JSONPath $self = shift;
    my $mod = shift || 0;
    return substr($self->{'jsonpath'}, $self->{'pos'} + $mod, 1);
}

sub current_char_is {
    my Validate::JSONPath $self = shift;
    my $val = shift;
    return ( substr($self->{'jsonpath'}, $self->{'pos'}, 1) eq $val );
}

sub is_whitespace {
    my Validate::JSONPath $self = shift;
    my $val = shift;
    return ( $val eq $SPACE or $val eq $TAB or $val eq $LF or $val eq $CR );
}

=head2 read_dot_token
    . and ..
=cut
sub read_dot_token {
    my Validate::JSONPath $self = shift;

    if ( $self->current_char() eq $PERIOD and $self->current_char(1) eq $PERIOD ) {
        #appender.appendPathToken(PathTokenFactory.crateScanToken());
        $self->{'pos'} += 2;
    } elsif ( ! $self->is_in_bounds() ) {
        die("($self->{'jsonpath'}) Path must not end with a '.");
    } else {
        $self->{'pos'}++;
    }
    if ( $self->current_char() eq $PERIOD ) {
        die("($self->{'jsonpath'}) Character '.' on position $self->{'pos'}' .
            ' is not valid.");
    }
    return $self->read_next_token();
}

=head2 read_property_or_function_token
    fooBar or fooBar()
=cut

sub read_property_or_function_token {
    my Validate::JSONPath $self = shift;

    if ( $self->current_char_is($OPEN_SQUARE_BRACKET) ||
        $self->current_char_is($WILDCARD) ||
        $self->current_char_is($PERIOD) ||
        $self->current_char_is($SPACE) ) {
        return;
    }
    my $startpos = $self->{'pos'};
    my $read_pos = $startpos;
    my $end_pos = 0;
    my $is_func = 0;

    while ( $self->is_in_bounds($read_pos) ) {
        my $current = substr($self->{'jsonpath'}, $read_pos, 1);
        if ( $current eq $SPACE ) {
            die("($self->{'jsonpath'}) Use bracket notion ['my prop'] if " .
                " your property contains blank characters. position: " .
                $self->{'pos'}
            );
        } elsif ( $current eq $PERIOD or $current eq $OPEN_SQUARE_BRACKET ) {
            $end_pos = $read_pos;
            last;
        } elsif ( $current eq $OPEN_PARENTHESIS ) {
            $is_func = 1;
            $end_pos = $read_pos++;
            last;
        }
        $read_pos++;
    }
    $end_pos = $self->{'jlen'} if ( $end_pos == 0 );

    if ( $is_func ) {
        if ( $self->{'pos'} + 1 < $self->{'jlen'} ) {
            my $next_char = substr($self->{'jsonpath'}, $read_pos + 1, 1);
            if ( $next_char eq $CLOSE_PARENTHESIS ) {
                $self->{'pos'} = $read_pos + 1;
            } else {
                $self->{'pos'} = $end_pos + 1;
                # parse the arguments of the function - arguments that are
                # inner queries or JSON document(s)
                my $func_name = substr(
                    $self->{'jsonpath'},
                    $startpos,
                    $end_pos - $startpos
                );
                $self->parse_function_parameters($func_name);
            }
        } else {
            $self->{'pos'} = $read_pos;
        }
    } else {
        $self->{'pos'} = $end_pos;
    }
    return 1 if ( ! $self->is_in_bounds() );
    return $self->read_next_token();
}


=head2 parse function
Parse the parameters of a function call, either the caller has supplied JSON data, or the caller has supplied
another path expression which must be evaluated and in turn invoked against the root document.  In this tokenizer
we're only concerned with parsing the path thus the output of this function is a list of parameters with the Path
set if the parameter is an expression.  If the parameter is a JSON document then the value of the cachedValue is
set on the object.

Sequence for parsing out the parameters:

This code has its own tokenizer - it does some rudimentary level of lexing in that it can distinguish between JSON block parameters
and sub-JSON blocks - it effectively regex's out the parameters into string blocks that can then be passed along to the appropriate parser.
Since sub-jsonpath expressions can themselves contain other function calls this routine needs to be sensitive to token counting to
determine the boundaries.  Since the Path parser isn't aware of JSON processing this uber routine is needed.

Parameters are separated by COMMAs ','

<pre>
doc = {"numbers": [1,2,3,4,5,6,7,8,9,10]}

$.sum({10}, $.numbers.avg())
</pre>

The above is a valid function call, we're first summing 10 + avg of 1...10 (5.5) so the total should be 15.5

@return
     An ordered list of parameters that are to processed via the function.  Typically functions either process
     an array of values and/or can consume parameters in addition to the values provided from the consumption of
     an array.
=cut

sub parse_function_parameters {
    my Validate::JSONPath $self = shift;
    my $func_name = shift;

    my $type;

    my ( $group_paren, $group_bracket, $group_brace, $group_quote ) = ( 1, (0) x 3 );
    #print "BEGIN group_quote=$group_quote\n";
    my $end_of_stream = 0;
    my $prior_char = 0;
    my $parameter;

    while ( $self->is_in_bounds() && ! $end_of_stream ) {
        my $current = $self->current_char();
        #print "pos = $self->{'pos'}, current=$current, parameter=$parameter\n";
        $self->{'pos'}++;

        if ( ! defined($type) ) {
            next if ( $self->is_whitespace($current) );

            if ( $current eq $OPEN_BRACE or $current =~ /^[0-9]$/ or $current eq $DOUBLE_QUOTE ) {
                $type = "JSON";
            } elsif ( $current eq $DOC_CONTEXT or $current == $EVAL_CONTEXT ) {
                $type = "PATH"; # read until we reach a terminating comma and we've reset grouping to zero
            }
        }

        if ( $current eq $DOUBLE_QUOTE ) {
            #print "inside double quote ($group_quote, type=$type)\n";
            if ( $prior_char ne "\\" and $group_quote > 0 ) {
                #print "about to decrement group quote\n";
                if ( $group_quote == 0 ) {
                    die("Unexpected quote '\"' at character position: "
                        . $self->{'pos'});
                }
                $group_quote--;
            } else {
                #print "increment group quote ($group_quote, type=$type)\n";
                $group_quote++;
            }
        } elsif ( $current eq $OPEN_PARENTHESIS ) {
            $group_paren++;
        } elsif ( $current eq $OPEN_BRACE ) {
            $group_brace++;
        } elsif ( $current eq $OPEN_SQUARE_BRACKET ) {
            $group_bracket++;
        } elsif ( $current eq $CLOSE_BRACE ) {
            if ( $group_brace == 0 ) {
                die("Unexpected close brace '}' at character position: "
                    . $self->{'pos'});
            }
            $group_brace--;
        } elsif ( $current eq $CLOSE_SQUARE_BRACKET ) {
            if ( $group_bracket == 0 ) {
                die("Unexpected close bracket ']' at character position: "
                    . $self->{'pos'});
            }
            $group_brace--;

        # In either the close paren case where we have zero paren groups left,
        # capture the parameter, or where we've encountered a COMMA do the same
        } elsif ( $current eq $CLOSE_PARENTHESIS or $current eq $COMMA ) {
            if ( $current eq $CLOSE_PARENTHESIS ) {
                $group_paren--;
                if ( $group_paren != 0 ) {
                    $parameter .= $current;
                }
            }
            die("Unquoted parameter: $parameter") if ( $group_quote );

            # In this state we've reach the end of a function parameter and we
            # can pass along the parameter string
            # to the parser
            if (
                (
                    0 == $group_quote
                    && 0 == $group_brace
                    && 0 == $group_bracket
                    && (
                        (
                            0 == $group_paren
                            && $CLOSE_PARENTHESIS == $current
                        )
                        ||
                        1 == $group_paren
                    )
                )
            ) {
                $end_of_stream = ( $group_paren == 0 );

                #print "inside! $parameter\n";

                if ( defined($type) ) {
                    $type = undef;
                    $parameter = undef;
                }
            }
        }

        if ( defined($type) and ! ( $current eq $COMMA && 0 == $group_brace && 0 == $group_bracket && 1 == $group_paren ) ) {
            $parameter .= $current;
        #} else {
        #    print "    not adding $current (current=$current, $group_brace, $group_bracket, $group_paren\n";
        }

        $prior_char = $current;
    }

    if ( 0 != $group_brace || 0 != $group_paren || 0 != $group_bracket ) {
        #print "!!! $group_brace $group_paren $group_bracket\n";
        die("Arguments to function: '$func_name' are not closed properly.");
    }
    return;
}

# [?], [?,?, ..]
sub read_placeholder_token {
    my Validate::JSONPath $self = shift;

    return if ( ! $self->current_char_is($OPEN_SQUARE_BRACKET) );

    my $question_mark_idx = $self->index_of_next_significant($BEGIN_FILTER);
    return if ( $question_mark_idx == -1 );

    my $next_sig = $self->next_significant_char($question_mark_idx);
    return if ( $next_sig ne $CLOSE_SQUARE_BRACKET and $next_sig ne $COMMA );

    my $exp_begin_index = $self->{'pos'} + 1;
    my $exp_end_index = $self->next_index_of(
        $CLOSE_SQUARE_BRACKET, $exp_begin_index
    );

    return if ( $exp_end_index == -1 );

    my $expression = substr(
        $self->{'jsonpath'},
        $exp_begin_index, $exp_end_index - $exp_begin_index
    );

    my @tokens = split(",", $expression);

    # XXX if filterStack < tokens.length

    foreach my $token ( @tokens ) {
        $token =~ s/^\s*//;
        $token =~ s/\s*$//;
        die("($self->{'jsonpath'}) Expected '?' but found $token")
            if ( $token ne "?" );
    }
    $self->{'pos'} = $exp_end_index + 1;

    return if ( $self->{'pos'} >= $self->{'jlen'} );

    return $self->read_next_token();
}

# [?(...)]
sub read_filter_token {
    my Validate::JSONPath $self = shift;

    return if ( ! $self->current_char_is($OPEN_SQUARE_BRACKET)
        and ! $self->index_of_next_significant($BEGIN_FILTER)
    );

    my $open_stmt_brck_idx = $self->{'pos'};
    my $question_mark_idx = $self->index_of_next_significant($BEGIN_FILTER);
    return if ( $question_mark_idx == -1 );

    my $open_brck_idx = $self->index_of_next_significant(
        $OPEN_PARENTHESIS,
        $question_mark_idx
    );
    return if ( $open_brck_idx == -1 );

    my $close_brck_idx = $self->index_of_closing(
        $open_brck_idx, $OPEN_PARENTHESIS, $CLOSE_PARENTHESIS, 1, 1
    );
    return if ( $close_brck_idx == -1 );

    return if ( ! $self->next_significant_char(
        $CLOSE_SQUARE_BRACKET,
        $close_brck_idx
    ));

    my $close_stmt_brck_idx = $self->index_of_next_significant(
        $CLOSE_SQUARE_BRACKET,
        $close_brck_idx,
    );

    # XXX what to do?  # Predicate predicate = FilterCompiler.compile(criteria);
    my $criteria = substr(
        $self->{'jsonpath'},
        $open_stmt_brck_idx,
        $close_stmt_brck_idx - $open_stmt_brck_idx + 1
    );
    $self->{'pos'} = $close_stmt_brck_idx + 1;

    return 1 if ( $self->{'pos'} >= $self->{'jlen'} );
    return $self->read_next_token();
}

sub read_wild_card_token {
    my Validate::JSONPath $self = shift;
    my $in_bracket = $self->current_char_is($OPEN_SQUARE_BRACKET);

    return if ( $in_bracket and ! $self->next_significant_char_is($WILDCARD) );

    return if (
        ! $self->current_char_is($WILDCARD)
        and ! $self->is_in_bounds($self->{'pos'} + 1)
    );

    if ( $in_bracket ) {
        my $wild_card_index = $self->index_of_next_significant($WILDCARD);
        if ( ! $self->next_significant_char_is(
            $CLOSE_SQUARE_BRACKET,
            $wild_card_index)
        ) {
            die("Expected wildcard token to end with ']' on pos: $wild_card_index");
        }
        my $brck_close_idx = $self->index_of_next_significant(
            $CLOSE_SQUARE_BRACKET,
            $wild_card_index,
        );
        $self->{'pos'} = $brck_close_idx + 1;
    } else {
        $self->{'pos'}++;
    }
    return 1 if ( $self->{'pos'} >= $self->{'jlen'} );
    return $self->read_next_token();
}

sub read_array_token {
    my Validate::JSONPath $self = shift;

    return if ( ! $self->current_char_is($OPEN_SQUARE_BRACKET) );

    #print "read array token\n";

    my $nxt_sig = $self->next_significant_char();

    #if (!isDigit(nextSignificantChar) && nextSignificantChar != MINUS && nextSignificantChar != SPLIT) {
    #print "nxt_sig ($nxt_sig)\n";

    if ( ! is_digit($nxt_sig) and $nxt_sig ne $MINUS and $nxt_sig ne $SPLIT ) {
        return;
    }

    my $exp_begin_index = $self->{'pos'} + 1;
    my $exp_end_index = $self->next_index_of(
        $CLOSE_SQUARE_BRACKET,
        $exp_begin_index
    );

    return if ( $exp_end_index == -1 );

    my $exp = substr(
        $self->{'jsonpath'},
        $exp_begin_index,
        $exp_end_index - $exp_begin_index
    );
    return if ( $exp eq "*" );
    return if ( $exp !~ /^[0-9\,\-\:\s]+$/ );

    if ( ":" eq $exp ) {
        # ArraySliceOperation arraySliceOperation = ArraySliceOperation.parse(expression);
    } else {
        # ArrayIndexOperation arrayIndexOperation = ArrayIndexOperation.parse(expression);
    }
    $self->{'jsonpath'} = $exp_end_index + 1;

    return 1 if ( ! $self->is_in_bounds() );
    return $self->read_next_token();
}

sub read_bracket_property_token {
    my Validate::JSONPath $self = shift;

    return if ( ! $self->current_char_is($OPEN_SQUARE_BRACKET) );

    my $pot_str_delim = $self->next_significant_char();
    if ( $pot_str_delim ne $SINGLE_QUOTE and $pot_str_delim ne $DOUBLE_QUOTE ) {
        return;
    }

    my $start_pos = $self->{'pos'} + 1;
    my $read_pos  = $start_pos;
    my $end_pos   = 0;
    my ( $in_property, $in_escape, $last_significant_was_comma );

    while ( $self->is_in_bounds($read_pos) ) {
        my $cc = $self->char_at($read_pos);
        if ( $in_escape ) {
            $in_escape = 0;
        } elsif ( $cc eq "\\" ) {
            $in_escape = 1;
        } elsif ( $cc eq $CLOSE_SQUARE_BRACKET and ! $in_property ) {
            if ( $last_significant_was_comma ) {
                die(
                    "($self->{'jsonpath'} Found empty property at index: " .
                    $read_pos
                );
            }
            last;
        } elsif ( $cc eq $pot_str_delim ) {
            if ( $in_property and ! $in_escape ) {
                my $next_sig_char = $self->next_significant_char($read_pos);
                if ( $next_sig_char ne $CLOSE_SQUARE_BRACKET
                    and $next_sig_char ne $COMMA
                ) {
                    die("Property must be separated by comma or Property " .
                        "must be terminated close square bracket at index " .
                        $read_pos
                    );
                }
                $end_pos = $read_pos;
                $in_property = 0;
            } else {
                $start_pos = $read_pos + 1;
                $in_property = 1;
                $last_significant_was_comma = 0;
            }
        } elsif ( $cc eq $COMMA ) {
            if ( $last_significant_was_comma ) {
                die("Found empty property at index $read_pos");
            }
            $last_significant_was_comma = 1;
        }
        $read_pos++;
    }
    my $end_brack_idx = $self->index_of_next_significant(
        $CLOSE_SQUARE_BRACKET, $end_pos
    ) + 1;
    $self->{'pos'} = $end_brack_idx;

    return 1 if ( ! $self->is_in_bounds() );
    return $self->read_next_token();
}

1;
