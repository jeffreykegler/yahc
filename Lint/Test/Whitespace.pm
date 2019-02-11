# Hoon whitespace "test" policy

package MarpaX::YAHC::Lint::Test::Whitespace;

use 5.010;
use strict;
use warnings;
no warnings 'recursion';

use Data::Dumper;
use English qw( -no_match_vars );
use Scalar::Util qw(looks_like_number weaken);

say STDERR join " ", __FILE__, __LINE__, "hi";


# TODO: delete ancestors, indents in favor of tree traversal

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub calcGapIndents {
    my ($node)     = @_;
    my $instance =  $MarpaX::YAHC::Lint::instance;
    my $symbolReverseDB = $instance->{symbolReverseDB};
    my $recce = $instance->{recce};
    my $children   = $node->{children};
    my @gapIndents = ();
    my $child      = $children->[0];
    my $childStart = $child->{start};
    my ( $childLine, $childColumn ) = $recce->line_column($childStart);
    push @gapIndents, [ $childLine, $childColumn - 1 ];
    for my $childIX ( 0 .. ( $#$children - 1 ) ) {
        my $child  = $children->[$childIX];
        my $symbol = $child->{symbol};
        if ( defined $symbol
            and $symbolReverseDB->{$symbol}->{gap} )
        {
            my $nextChild = $children->[ $childIX + 1 ];
            my $nextStart = $nextChild->{start};
            my ( $nextLine, $nextColumn ) = $recce->line_column($nextStart);
            push @gapIndents, [ $nextLine, $nextColumn - 1 ];
        }
    }
    return \@gapIndents;
}

sub is_0Jogging {
    my ( $runeLine, $runeColumn, $gapIndents ) = @_;
    my $instance =  $MarpaX::YAHC::Lint::instance;
    my $lineToPos = $instance->{lineToPos};
    my @mistakes = ();
    die "Jogging-0-style rule with only $gapIndents gap indents"
      if $#$gapIndents < 2;

    # Second child must be on rune line, or
    # at ruleColumn+2
    my ( $firstChildLine, $firstChildColumn ) =
      @{ $gapIndents->[1] };

    if (    $firstChildLine != $runeLine
        and $firstChildColumn != $runeColumn + 2 )
    {
        my $msg = sprintf "Jogging-0-style child #%d @%d:%d; %s", 2,
          $firstChildLine,
          $firstChildColumn + 1,
          describeMisindent( $firstChildColumn, $runeColumn + 2 );
        push @mistakes,
          {
            desc           => $msg,
            line           => $firstChildLine,
            column         => $firstChildColumn,
            child          => 2,
            expectedColumn => $runeColumn + 2,
          };
    }

    my ( $tistisLine, $tistisColumn ) = @{ $gapIndents->[2] };
    if ( $tistisLine == $runeLine ) {
        my $msg = sprintf
          "Jogging-0-style line %d; TISTIS is on rune line %d; should not be",
          $runeLine, $tistisLine;
        push @mistakes,
          {
            desc         => $msg,
            line         => $tistisLine,
            column       => $tistisColumn,
            child        => 3,
            expectedLine => $runeLine,
          };
    }

    my $tistisIsMisaligned = $tistisColumn != $runeColumn;

    # say join " ", __FILE__, __LINE__, $tistisColumn , $runeColumn;
    if ($tistisIsMisaligned) {
        my $tistisPos = $lineToPos->[$tistisLine] + $tistisColumn;
        my $tistis = literal( $tistisPos, 2 );

        # say join " ", __FILE__, __LINE__, $tistis;
        $tistisIsMisaligned = $tistis ne '==';
    }
    if ($tistisIsMisaligned) {
        my $msg = sprintf "Jogging-0-style; TISTIS @%d:%d; %s",
          $tistisLine, $tistisColumn + 1,
          describeMisindent( $tistisColumn, $runeColumn );
        push @mistakes,
          {
            desc           => $msg,
            line           => $tistisLine,
            column         => $tistisColumn,
            child          => 3,
            expectedColumn => $runeColumn,
          };
    }
    return \@mistakes;
}

sub validate {
    my ( $policy, $instance, $node, $argContext ) = @_;

    my $fileName = $instance->{fileName};
    my $grammar = $instance->{grammar};
    my $recce = $instance->{recce};
    my $mortarLHS = $instance->{mortarLHS};

    my $tallRuneRule = $instance->{tallRuneRule};
    my $tallJogRule = $instance->{tallJogRule};
    my $tallNoteRule = $instance->{tallNoteRule};
    my $tallLuslusRule = $instance->{tallLuslusRule};
    my $tall_0JoggingRule = $instance->{tall_0JoggingRule};
    my $tall_1JoggingRule = $instance->{tall_1JoggingRule};
    my $tall_2JoggingRule = $instance->{tall_2JoggingRule};
    my $tallJogging1_Rule = $instance->{tallJogging1_Rule};

    my $ruleDB = $instance->{ruleDB};
    my $suppressions = $instance->{suppressions};
    my $unusedSuppressions = $instance->{unusedSuppressions};
    my $inclusions = $instance->{inclusions};
    my $lineToPos = $instance->{lineToPos};
    my $symbolReverseDB = $instance->{symbolReverseDB};
    my $censusWhitespace = $instance->{censusWhitespace};

    my $parentSymbol = $node->{symbol};
    my $parentStart  = $node->{start};
    my $parentLength = $node->{length};
    my $parentRuleID = $node->{ruleID};

    $Data::Dumper::Maxdepth = 3;
    say Data::Dumper::Dumper($node);

    my ( $parentLine, $parentColumn ) = $instance->line_column($parentStart);
    my $parentLC = join ':', $parentLine, $parentColumn+1;

    my @parentIndents = @{ $argContext->{indents} };

    # TODO: Delete "ancestors" in favor of tree traversal
    my @ancestors = @{ $argContext->{ancestors} };
    shift @ancestors if scalar @ancestors >= 5;    # no more than 5
    push @ancestors, { ruleID => $parentRuleID, start => $parentStart };

    my $argLine = $argContext->{line};
    if ( $argLine != $parentLine ) {
        @parentIndents = ($parentColumn);

        # say "line $parentLine: new indents: ", (join " ", @parentIndents);
    }
    elsif ( $parentColumn != $parentIndents[$#parentIndents] ) {
        push @parentIndents, $parentColumn;

        # say "line $parentLine: indents: ", (join " ", @parentIndents);
    }

    my $argBodyIndent     = $argContext->{bodyIndent};
    my $argTallRuneIndent = $argContext->{tallRuneIndent};
    my $parentBodyIndent;
    $parentBodyIndent = $argBodyIndent if $argLine == $parentLine;
    my $parentTallRuneIndent;
    $parentTallRuneIndent = $argTallRuneIndent if $argLine == $parentLine;
    my $parentContext = {
        ancestors => \@ancestors,
        line      => $parentLine,
        indents   => [@parentIndents],
    };
    $parentContext->{bodyIndent} = $parentBodyIndent
      if defined $parentBodyIndent;
    $parentContext->{tallRuneIndent} = $parentTallRuneIndent
      if defined $parentTallRuneIndent;

    # notes align with body indent from ancestor, if there is one;
    # otherwise, with the parent tall rune (if one exists);
    # otherwise with the parent.
    my $noteIndent = ( $parentBodyIndent // $parentTallRuneIndent )
      // $parentColumn;

    my $parentChessSide = $argContext->{chessSide};
    $parentContext->{chessSide} = $parentChessSide
      if defined $parentChessSide;

    my $parentJogRuneColumn = $argContext->{jogRuneColumn};
    $parentContext->{jogRuneColumn} = $parentJogRuneColumn
      if defined $parentJogRuneColumn;

    my $parentJogBodyColumn = $argContext->{jogBodyColumn};
    $parentContext->{jogBodyColumn} = $parentJogBodyColumn
      if defined $parentJogBodyColumn;

    my $parentHoonName = $argContext->{hoonName};
    # say STDERR "setting hoonName = $parentHoonName";
    $parentContext->{hoonName} = $parentHoonName;

    my $children = $node->{children};

    my $nodeType = $node->{type};
    last WHITESPACE_POLICY if $nodeType ne 'node';

    my $ruleID = $node->{ruleID};
    my ( $lhs, @rhs ) = $grammar->rule_expand( $node->{ruleID} );
    my $lhsName = $grammar->symbol_name($lhs);

    # say STDERR join " ", __FILE__, __LINE__, $lhsName;

 # say STDERR "current hoonName = $parentHoonName ", $parentContext->{hoonName};
    if ( not $mortarLHS->{$lhsName} ) {
        $parentHoonName = $lhsName;

        # say STDERR "resetting hoonName = $parentHoonName";
        $parentContext->{hoonName} = $parentHoonName;
    }

    $parentContext->{bodyIndent} = $parentColumn
      if $instance->{tallBodyRule}->{$lhsName};

    $parentContext->{tallRuneIndent} = $parentColumn
      if $tallRuneRule->{$lhsName};

    if ( $lhsName eq 'optGay4i' ) {
        last WHITESPACE_POLICY;
    }

    my $childCount = scalar @{$children};
    last WHITESPACE_POLICY if $childCount <= 0;
    if ( $childCount == 1 ) {
        last WHITESPACE_POLICY;
    }

    my $firstChildIndent = column( $children->[0]->{start} ) - 1;

    my $gapiness = $ruleDB->[$ruleID]->{gapiness} // 0;

    my $reportType = $gapiness < 0 ? 'sequence' : 'indent';

    # TODO: In another policy, warn on tall children of wide nodes
    if ( $gapiness == 0 ) {    # wide node
        last WHITESPACE_POLICY;
    }

    # tall node

    if ( $gapiness < 0 ) {     # sequence
        my ( $parentLine, $parentColumn ) = $recce->line_column($parentStart);
        my $parentLC = join ':', $parentLine, $parentColumn;
        $parentColumn--;       # 0-based
        my $previousLine = $parentLine;
      TYPE_INDENT: {

            # Jogging problems are detected by the individual jogs --
            # we do not run diagnostics on the sequence.
            next TYPE_INDENT if $lhsName eq 'rick5d';
            next TYPE_INDENT if $lhsName eq 'ruck5d';

            if ( $lhsName eq 'tall5dSeq' ) {
                my $argAncestors = $argContext->{ancestors};

                # say Data::Dumper::Dumper($argAncestors);
                my $ancestorCount   = scalar @{$argAncestors};
                my $grandParentName = "";
                my $grandParentLC;
                my ( $grandParentLine, $grandParentColumn );
                if ( scalar @{$argAncestors} >= 1 ) {
                    my $grandParent       = $argAncestors->[-1];
                    my $grandParentRuleID = $grandParent->{ruleID};
                    my $grandParentStart  = $grandParent->{start};
                    ( $grandParentLine, $grandParentColumn ) =
                      $recce->line_column($grandParentStart);
                    $grandParentLC = join ':', $grandParentLine,
                      $grandParentColumn;
                    $grandParentColumn--;    # 0-based
                    my ($lhs) = $grammar->rule_expand($grandParentRuleID);
                    $grandParentName = $grammar->symbol_display_form($lhs);
                }
                if ( $grandParentName eq 'tallSemsig' ) {

                    $previousLine = $grandParentLine;
                  CHILD: for my $childIX ( 0 .. $#$children ) {
                        my $isProblem  = 0;
                        my $child      = $children->[$childIX];
                        my $childStart = $child->{start};
                        my $symbol     = $child->{symbol};
                        next CHILD
                          if defined $symbol
                          and $symbolReverseDB->{$symbol}->{gap};
                        my ( $childLine, $childColumn ) =
                          $recce->line_column($childStart);
                        my $childLC = join ':', $childLine, $childColumn;
                        $childColumn--;    # 0-based

                        my $indentDesc = 'RUN';
                      SET_INDENT_DESC: {
                            my $suppression =
                              $suppressions->{'sequence'}{$childLC};
                            if ( defined $suppression ) {
                                $indentDesc = "SUPPRESSION $suppression";
                                $unusedSuppressions->{'sequence'}{$childLC} =
                                  undef;
                                last SET_INDENT_DESC;
                            }

                            if (    $childLine != $previousLine
                                and $childColumn != $grandParentColumn + 2 )
                            {
                                $isProblem = 1;
                                $indentDesc = join " ", $grandParentLC,
                                  $childLC;
                            }
                        }
                        if ( not $inclusions
                            or $inclusions->{sequence}{$childLC} )
                        {
                            reportItem(
"$fileName $childLC sequence $lhsName $indentDesc",
                                $parentLine,
                                $childLine
                            ) if $censusWhitespace or $isProblem;
                        }
                        $previousLine = $childLine;
                    }

                    last TYPE_INDENT;
                }
            }

          CHILD: for my $childIX ( 0 .. $#$children ) {
                my $isProblem  = 0;
                my $child      = $children->[$childIX];
                my $childStart = $child->{start};
                my $symbol     = $child->{symbol};
                next CHILD
                  if defined $symbol
                  and $symbolReverseDB->{$symbol}->{gap};
                my ( $childLine, $childColumn ) =
                  $recce->line_column($childStart);
                my $childLC = join ':', $childLine, $childColumn;
                $childColumn--;    # 0-based

                my $indentDesc = 'REGULAR';
              SET_INDENT_DESC: {
                    my $suppression = $suppressions->{'sequence'}{$childLC};
                    if ( defined $suppression ) {
                        $indentDesc = "SUPPRESSION $suppression";
                        $unusedSuppressions->{'sequence'}{$childLC} = undef;
                        last SET_INDENT_DESC;
                    }

                    if (    $childLine != $previousLine
                        and $childColumn != $parentColumn )
                    {
                        $isProblem = 1;
                        $indentDesc = join " ", $parentLC, $childLC;
                    }
                }
                if ( not $inclusions
                    or $inclusions->{sequence}{$childLC} )
                {
                    reportItem(
                        (
                            sprintf
                              "$fileName $childLC sequence %s $indentDesc",
                            diagName( $node, $parentContext )
                        ),
                        $parentLine,
                        $childLine,
                    ) if $censusWhitespace or $isProblem;
                }
                $previousLine = $childLine;
            }
        }
        last WHITESPACE_POLICY;
    }

    sub isLuslusStyle {
        my ($indents) = @_;
        my @mistakes = ();
        my ( $baseLine, $baseColumn ) = @{ $indents->[0] };

        my $indentCount = scalar @{$indents};
        my $indentIX    = 1;
      INDENT: while ( $indentIX < $indentCount ) {
            my ( $thisLine, $thisColumn ) = @{ $indents->[$indentIX] };
            last INDENT if $thisLine != $baseLine;
            $indentIX++;
        }
      INDENT: while ( $indentIX < $indentCount ) {
            my ( $thisLine, $thisColumn ) = @{ $indents->[$indentIX] };
            if ( $thisColumn != $baseColumn + 2 ) {
                my $msg = sprintf
                  "Child #%d @ line %d; backdent is %d; should be %d",
                  $indentIX, $thisLine, $thisColumn, $baseColumn + 2;
                push @mistakes,
                  {
                    desc           => $msg,
                    line           => $thisLine,
                    column         => $thisColumn,
                    child          => $indentIX,
                    expectedColumn => $baseColumn + 2
                  };
            }
            $indentIX++;
        }
        return \@mistakes;
    }

    # Format line and 0-based column as string
    sub describeLC {
        my ( $line, $column ) = @_;
        return '@' . $line . ':' . ( $column + 1 );
    }

    sub describeMisindent {
        my ( $got, $sought ) = @_;
        if ( $got > $sought ) {
            return "overindented by " . ( $got - $sought );
        }
        if ( $got < $sought ) {
            return "underindented by " . ( $sought - $got );
        }
        return "correctly indented";
    }

    my $joggingSide = sub {
        my ( $node, $runeColumn ) = @_;
        my $children  = $node->{children};
        my %sideCount = ();
        my $firstSide;
        my %bodyColumnCount = ();
        my $kingsideCount   = 0;
        my $queensideCount  = 0;
      CHILD: for my $childIX ( 0 .. $#$children ) {
            my $jog    = $children->[$childIX];
            my $symbol = $jog->{symbol};
            next CHILD if defined $symbol and $symbolReverseDB->{$symbol}->{gap};
            my $head = $jog->{children}->[0];
            my ( undef, $column1 ) = $instance->line_column( $head->{start} );

            # say " $column1 - $runeColumn >= 4 ";
            if ( $column1 - $runeColumn >= 4 ) {
                $queensideCount++;
                next CHILD;
            }
            $kingsideCount++;
        }
        return $kingsideCount > $queensideCount
          ? 'kingside'
          : 'queenside';
    };

    my $joggingBodyAlignment = sub {
        my ( $node, $runeColumn ) = @_;
        my $children = $node->{children};
        my $firstBodyColumn;
        my %firstLine       = ();
        my %bodyColumnCount = ();

        # Traverse first to last to make it easy to record
        # first line of occurrence of each body column
      CHILD:
        for ( my $childIX = $#$children ; $childIX >= 0 ; $childIX-- ) {
            my $jog         = $children->[$childIX];
            my $jogChildren = $jog->{children};
            my $head        = $jogChildren->[1];
            my $gap         = $jogChildren->[1];
            my $body        = $jogChildren->[2];
            my ( $bodyLine, $bodyColumn ) =
              $instance->line_column( $body->{start} );
            my ( $headLine, $headColumn ) =
              $instance->line_column( $head->{start} );
            my $gapLength = $gap->{length};
            $firstBodyColumn = $bodyColumn
              if not defined $firstBodyColumn;
            next CHILD unless $headLine == $bodyLine;
            next CHILD unless $gap > 2;
            $bodyColumnCount{$bodyColumn} = $bodyColumnCount{$bodyColumn}++;
            $firstLine{$bodyColumn}       = $bodyLine;
        }
        my @bodyColumns = keys %bodyColumnCount;

        # If no aligned columns, simply return first
        return $firstBodyColumn if not @bodyColumns;

        my @sortedBodyColumns =
          sort {
                 $bodyColumnCount{$a} <=> $bodyColumnCount{$b}
              or $firstLine{$b} <=> $firstLine{$a}
          }
          keys %bodyColumnCount;
        my $topBodyColumn = $sortedBodyColumns[$#sortedBodyColumns];
        return $topBodyColumn;
    };

    my $censusJoggingHoon = sub {
        my ($node) = @_;
        my ( undef, $runeColumn ) = $instance->line_column( $node->{start} );
      CHILD: for my $childIX ( 0 .. $#$children ) {
            my $child  = $children->[$childIX];
            my $symbol = symbol($child);
            next CHILD if $symbol ne 'rick5d' and $symbol ne 'ruck5d';
            my $side = $joggingSide->( $child, $runeColumn );
            my $bodyAlignment = $joggingBodyAlignment->( $child, $runeColumn );
            return $side, $bodyAlignment;
        }
        die "No jogging found for ", symbol($node);
    };

    my $isJogging1 = sub {
        my ( $context, $node, $gapIndents ) = @_;
        my $start = $node->{start};
        my ( $runeLine,  $runeColumn )    = $instance->line_column($start);
        my ( $chessSide, $jogBodyColumn ) = $censusJoggingHoon->($node);
        $context->{chessSide} = $chessSide;

        # say join " ", __FILE__, __LINE__, "set chess side:", $chessSide;
        $context->{jogRuneColumn} = $runeColumn;

# say join " ", __FILE__, __LINE__, "set rune column:", $context->{jogRuneColumn} ;

        $context->{jogBodyColumn} = $jogBodyColumn
          if defined $jogBodyColumn;
        internalError("Chess side undefined") unless $chessSide;

        # say join " ", "=== jog census:", $side, ($flatJogColumn // 'na');
        my @mistakes = ();
        die "1-jogging rule with only $gapIndents gap indents"
          if $#$gapIndents < 3;
        my ( $firstChildLine, $firstChildColumn ) =
          @{ $gapIndents->[1] };
        if ( $firstChildLine != $runeLine ) {
            my $msg = sprintf
              "1-jogging %s head %s; should be on rune line %d",
              $chessSide,
              describeLC( $firstChildLine, $firstChildColumn ),
              $runeLine;
            push @mistakes,
              {
                desc         => $msg,
                line         => $firstChildLine,
                column       => $firstChildColumn,
                child        => 1,
                expectedLine => $runeLine,
              };
        }

        my $expectedColumn = $runeColumn + ( $chessSide eq 'kingside' ? 4 : 6 );
        if ( $firstChildColumn != $expectedColumn ) {
            my $msg = sprintf
              "1-jogging %s head %s; %s",
              $chessSide,
              describeLC( $firstChildLine, $firstChildColumn ),
              describeMisindent( $firstChildColumn, $expectedColumn );
            push @mistakes,
              {
                desc           => $msg,
                line           => $firstChildLine,
                column         => $firstChildColumn,
                child          => 1,
                expectedColumn => $expectedColumn,
              };
        }

        my ( $tistisLine, $tistisColumn ) = @{ $gapIndents->[3] };
        if ( $tistisLine == $runeLine ) {
            my $msg = sprintf
              "1-jogging TISTIS %s; should not be on rune line",
              $chessSide,
              describeLC( $tistisLine, $tistisColumn );
            push @mistakes,
              {
                desc         => $msg,
                line         => $tistisLine,
                column       => $tistisColumn,
                child        => 3,
                expectedLine => $runeLine,
              };
        }

        my $tistisIsMisaligned = $tistisColumn != $runeColumn;

        # say join " ", __FILE__, __LINE__, $tistisColumn , $runeColumn;
        if ($tistisIsMisaligned) {
            my $tistisPos = $lineToPos->[$tistisLine] + $tistisColumn;
            my $tistis = literal( $tistisPos, 2 );

            # say join " ", __FILE__, __LINE__, $tistis;
            $tistisIsMisaligned = $tistis ne '==';
        }
        if ($tistisIsMisaligned) {
            my $msg = sprintf "1-jogging TISTIS %s; %s",
              describeLC( $tistisLine, $tistisColumn ),
              describeMisindent( $tistisColumn, $runeColumn );
            push @mistakes,
              {
                desc           => $msg,
                line           => $tistisLine,
                column         => $tistisColumn,
                child          => 3,
                expectedColumn => $runeColumn,
              };
        }
        return \@mistakes;
    };

    my $isJogging2 = sub {
        my ( $context, $node, $gapIndents ) = @_;
        my $start = $node->{start};
        my ( $runeLine,  $runeColumn )    = $instance->line_column($start);
        my ( $chessSide, $jogBodyColumn ) = $censusJoggingHoon->($node);
        $context->{chessSide} = $chessSide;

        # say join " ", __FILE__, __LINE__, "set chess side:", $chessSide;
        $context->{jogRuneColumn} = $runeColumn;
        $context->{jogBodyColumn} = $jogBodyColumn if $jogBodyColumn;
        internalError("Chess side undefined") unless $chessSide;

        # say join " ", "=== jog census:", $side, ($flatJogColumn // 'na');
        my @mistakes = ();
        my ( $firstChildLine, $firstChildColumn ) =
          @{ $gapIndents->[1] };
        if ( $firstChildLine != $runeLine ) {
            my $msg = sprintf
"Jogging-2-style child #%d @ line %d; first child is on line %d; should be on rune line",
              1, $runeLine, $firstChildLine;
            push @mistakes,
              {
                desc         => $msg,
                line         => $firstChildLine,
                column       => $firstChildColumn,
                child        => 1,
                expectedLine => $runeLine,
              };
        }

        my $expectedColumn = $runeColumn + ( $chessSide eq 'kingside' ? 6 : 8 );
        if ( $firstChildColumn != $expectedColumn ) {
            my $msg = sprintf
              "Jogging-2-style %s child #%d @%d:%d; %s",
              $chessSide, 1, $runeLine,
              $firstChildColumn + 1,
              describeMisindent( $firstChildColumn, $expectedColumn );
            push @mistakes,
              {
                desc           => $msg,
                line           => $firstChildLine,
                column         => $firstChildColumn,
                child          => 1,
                expectedColumn => $expectedColumn,
              };
        }

        # Second child must be on rune line, or
        # at chess-side-dependent column
        $expectedColumn = $runeColumn + ( $chessSide eq 'kingside' ? 4 : 6 );
        my ( $secondChildLine, $secondChildColumn ) =
          @{ $gapIndents->[2] };

        if (    $secondChildLine != $runeLine
            and $secondChildColumn != $expectedColumn )
        {
            my $msg = sprintf
              "Jogging-2-style %s child #%d @%d:%d; %s",
              $chessSide, 2, $secondChildLine,
              $secondChildColumn + 1,
              describeMisindent( $secondChildColumn, $expectedColumn );
            push @mistakes,
              {
                desc           => $msg,
                line           => $secondChildLine,
                column         => $secondChildColumn,
                child          => 2,
                expectedColumn => $expectedColumn,
              };
        }

        my ( $tistisLine, $tistisColumn ) = @{ $gapIndents->[4] };
        if ( $tistisLine == $runeLine ) {
            my $msg = sprintf
"Jogging-2-style line %d; TISTIS is on rune line %d; should not be",
              $runeLine, $tistisLine;
            push @mistakes,
              {
                desc         => $msg,
                line         => $tistisLine,
                column       => $tistisColumn,
                child        => 3,
                expectedLine => $runeLine,
              };
        }

        my $tistisIsMisaligned = $tistisColumn != $runeColumn;

        # say join " ", __FILE__, __LINE__, $tistisColumn , $runeColumn;
        if ($tistisIsMisaligned) {
            my $tistisPos = $lineToPos->[$tistisLine] + $tistisColumn;
            my $tistis = literal( $tistisPos, 2 );

            # say join " ", __FILE__, __LINE__, $tistis;
            $tistisIsMisaligned = $tistis ne '==';
        }
        if ($tistisIsMisaligned) {
            my $msg = sprintf "Jogging-2-style; TISTIS @%d:%d; %s",
              $tistisLine, $tistisColumn + 1,
              describeMisindent( $tistisColumn, $runeColumn );
            push @mistakes,
              {
                desc           => $msg,
                line           => $tistisLine,
                column         => $tistisColumn,
                child          => 3,
                expectedColumn => $runeColumn,
              };
        }
        return \@mistakes;
    };

    my $isJogging_1 = sub {
        my ( $context, $node, $gapIndents ) = @_;
        my $start = $node->{start};
        my ( $runeLine,  $runeColumn )    = $instance->line_column($start);
        my ( $chessSide, $jogBodyColumn ) = $censusJoggingHoon->($node);
        $context->{chessSide} = $chessSide;

        # say join " ", __FILE__, __LINE__, "set chess side:", $chessSide;
        $context->{jogRuneColumn} = $runeColumn;
        $context->{jogBodyColumn} = $jogBodyColumn if defined $jogBodyColumn;
        internalError("Chess side undefined") unless $chessSide;

        # say join " ", "=== jog census:", $side, ($flatJogColumn // 'na');
        my @mistakes = ();
        die "Jogging-prefix rule with only $gapIndents gap indents"
          if $#$gapIndents < 3;

        my ( $tistisLine, $tistisColumn ) = @{ $gapIndents->[2] };
        if ( $tistisLine == $runeLine ) {
            my $msg = sprintf
"Jogging-prefix line %d; TISTIS is on rune line %d; should not be",
              $runeLine, $tistisLine;
            push @mistakes,
              {
                desc         => $msg,
                line         => $tistisLine,
                column       => $tistisColumn,
                child        => 3,
                expectedLine => $runeLine,
              };
        }

        my $expectedColumn     = $runeColumn + 2;
        my $tistisIsMisaligned = $tistisColumn != $expectedColumn;

        # say join " ", __FILE__, __LINE__, $tistisColumn , $runeColumn;
        if ($tistisIsMisaligned) {
            my $tistisPos = $lineToPos->[$tistisLine] + $tistisColumn;
            my $tistis = literal( $tistisPos, 2 );

            # say join " ", __FILE__, __LINE__, $tistis;
            $tistisIsMisaligned = $tistis ne '==';
        }
        if ($tistisIsMisaligned) {
            my $msg = sprintf "Jogging-prefix; TISTIS @%d:%d; %s",
              $tistisLine, $tistisColumn + 1,
              describeMisindent( $tistisColumn, $runeColumn );
            push @mistakes,
              {
                desc           => $msg,
                line           => $tistisLine,
                column         => $tistisColumn,
                child          => 3,
                expectedColumn => $expectedColumn,
              };
        }

        my ( $thirdChildLine, $thirdChildColumn ) =
          @{ $gapIndents->[3] };

        # TODO: No examples of "jogging prefix" queenside in arvo/ corpus
        $expectedColumn = $runeColumn;
        if ( $thirdChildColumn != $expectedColumn ) {
            my $msg = sprintf
              "Jogging-prefix %s child #%d @%d:%d; %s",
              $chessSide, 1, $runeLine,
              $thirdChildColumn + 1,
              describeMisindent( $thirdChildColumn, $expectedColumn );
            push @mistakes,
              {
                desc           => $msg,
                line           => $thirdChildLine,
                column         => $thirdChildColumn,
                child          => 1,
                expectedColumn => $expectedColumn,
              };
        }

        return \@mistakes;
    };

    my $checkKingsideJog = sub {
        my ( $node, $context ) = @_;

 # say join " ", __FILE__, __LINE__, "rune column:", $context->{jogRuneColumn} ;
        my $chessSide = $context->{chessSide};
        say STDERR Data::Dumper::Dumper(
            [
                $context->{hoonName},
                $fileName,
                ( $instance->line_column( $node->{start} ) ),
                map { $grammar->symbol_display_form($_) }
                  $grammar->rule_expand($ruleID)
            ]
        ) unless $chessSide;    # TODO: Delete after development
        internalError("Chess side undefined") unless $chessSide;

        my @mistakes = ();

        my $runeColumn = $context->{jogRuneColumn};
        say STDERR Data::Dumper::Dumper(
            [
                $context->{hoonName},
                $fileName,
                ( $instance->line_column( $node->{start} ) ),
                map { $grammar->symbol_display_form($_) }
                  $grammar->rule_expand($ruleID)
            ]
        ) unless defined $runeColumn;    # TODO: Delete after development
        internalError("Rune column undefined") unless defined $runeColumn;
        my $jogBodyColumn = $context->{jogBodyColumn};

 # say join " ", __FILE__, __LINE__, "rune column:", $context->{jogRuneColumn} ;

        # do not pass these attributes on to child nodes
        delete $context->{jogRuneColumn};
        delete $context->{jogBodyColumn};
        delete $context->{chessSide};

        # Replace inherited attribute rune LC with brick LC
        my ( $brickLine, $brickColumn ) = MarpaX::YAHC::Lint::brickLC($node);

        my $children = $node->{children};
        my $head     = $children->[0];
        my $gap      = $children->[1];
        my $body     = $children->[2];
        my ( $headLine, $headColumn ) =
          $instance->line_column( $head->{start} );
        my ( $bodyLine, $bodyColumn ) =
          $instance->line_column( $body->{start} );
        my $sideDesc = 'kingside';

        my $expectedHeadColumn = $runeColumn + 2;
        if ( $headColumn != $expectedHeadColumn ) {
            my $msg = sprintf 'Jog %s head %s; %s',
              $sideDesc,
              describeLC( $headLine, $headColumn ),
              describeMisindent( $headColumn, $expectedHeadColumn );
            push @mistakes,
              {
                desc           => $msg,
                line           => $headLine,
                column         => $headColumn,
                child          => 1,
                expectedColumn => $expectedHeadColumn,
                topicLines     => [$brickLine],
              };
        }

        if ( $headLine != $bodyLine ) {

            my $expectedBodyColumn = $runeColumn + 4;
            if ( $bodyColumn != $expectedBodyColumn ) {
                my $msg = sprintf 'Jog %s body %s; %s',
                  $sideDesc, describeLC( $bodyLine, $bodyColumn ),
                  describeMisindent( $bodyColumn, $expectedBodyColumn );
                push @mistakes,
                  {
                    desc           => $msg,
                    line           => $bodyLine,
                    column         => $bodyColumn,
                    child          => 2,
                    expectedColumn => $expectedBodyColumn,
                    topicLines     => [$brickLine],
                  };
            }
            return \@mistakes;
        }

        # Check for flat kingside misalignments
        my $gapLength = $gap->{length};
        if ( $gapLength != 2 and $bodyColumn != $jogBodyColumn ) {
            my $msg = sprintf 'Jog %s body %s; %s',
              $sideDesc,
              describeLC( $bodyLine, $bodyColumn ),
              describeMisindent( $bodyColumn, $jogBodyColumn );
            push @mistakes,
              {
                desc           => $msg,
                line           => $bodyLine,
                column         => $bodyColumn,
                child          => 2,
                expectedColumn => $jogBodyColumn,
                topicLines     => [$brickLine],
              };
        }
        return \@mistakes;
    };

    my $checkQueensideJog = sub {
        my ( $node, $context ) = @_;

# say join " ", __FILE__, __LINE__, "set rune column:", $context->{jogRuneColumn} ;
        my $chessSide = $context->{chessSide};
        die Data::Dumper::Dumper(
            [
                $fileName,
                ( $instance->line_column( $node->{start} ) ),
                map { $grammar->symbol_display_form($_) }
                  $grammar->rule_expand($ruleID)
            ]
        ) unless $chessSide;    # TODO: Delete after development
        internalError("Chess side undefined") unless $chessSide;

        my @mistakes = ();

        my $runeColumn    = $context->{jogRuneColumn};
        my $jogBodyColumn = $context->{jogBodyColumn};

        # do not pass these attributes on to child nodes
        delete $context->{jogRuneColumn};
        delete $context->{jogBodyColumn};
        delete $context->{chessSide};

        # Replace inherited attribute rune LC with brick LC
        my ( $brickLine, $brickColumn ) = MarpaX::YAHC::Lint::brickLC($node);

        my $children = $node->{children};
        my $head     = $children->[0];
        my $gap      = $children->[1];
        my $body     = $children->[2];
        my ( $headLine, $headColumn ) =
          $instance->line_column( $head->{start} );
        my ( $bodyLine, $bodyColumn ) =
          $instance->line_column( $body->{start} );
        my $sideDesc = 'queenside';

        my $expectedHeadColumn = $runeColumn + 4;
        if ( $headColumn != $expectedHeadColumn ) {
            my $msg = sprintf 'Jog %s head %s; %s',
              $sideDesc,
              describeLC( $headLine, $headColumn ),
              describeMisindent( $headColumn, $expectedHeadColumn );
            push @mistakes,
              {
                desc           => $msg,
                line           => $headLine,
                column         => $headColumn,
                child          => 1,
                expectedColumn => $expectedHeadColumn,
                topicLines     => [$brickLine],
              };
        }

        my $expectedBodyColumn = $runeColumn + 2;
        if (    $headLine != $bodyLine
            and $bodyColumn != $expectedBodyColumn )
        {

            my $msg = sprintf 'Jog %s body %s; %s',
              $sideDesc,
              describeLC( $bodyLine, $bodyColumn ),
              describeMisindent( $bodyColumn, $expectedBodyColumn );
            push @mistakes,
              {
                desc           => $msg,
                line           => $bodyLine,
                column         => $bodyColumn,
                child          => 2,
                expectedColumn => $expectedBodyColumn,
                topicLines     => [$brickLine],
              };
        }

        # Check for flat queenside misalignments
        if ( $headLine == $bodyLine ) {
            $expectedBodyColumn = $jogBodyColumn;
            my $gapLength = $gap->{length};
            if ( $gapLength != 2 and $bodyColumn != $jogBodyColumn ) {
                my $msg = sprintf 'Jog %s body %s; %s',
                  $sideDesc,
                  describeLC( $bodyLine, $bodyColumn ),
                  describeMisindent( $bodyColumn, $jogBodyColumn );
                push @mistakes,
                  {
                    desc           => $msg,
                    line           => $bodyLine,
                    column         => $bodyColumn,
                    child          => 2,
                    expectedColumn => $jogBodyColumn,
                    topicLines     => [$brickLine],
                  };
            }
        }
        return \@mistakes;
    };

    # TODO: Add a check (optional?) for queenside joggings with no
    # split jogs.
    my $isJog = sub {
        my ( $node, $context ) = @_;

# say join " ", __FILE__, __LINE__, "set rune column:", $context->{jogRuneColumn} ;
        my $chessSide = $context->{chessSide};
        return $checkQueensideJog->( $node, $context )
          if $chessSide eq 'queenside';
        return $checkKingsideJog->( $node, $context );
    };

    sub isBackdented {
        my ( $indents, $baseIndent ) = @_;
        my @mistakes = ();

        # say Data::Dumper::Dumper($indents);
        my ( $baseLine, $baseColumn ) = @{ $indents->[0] };
        $baseIndent //= $baseColumn;
        my $currentIndent = $baseIndent + $#$indents * 2;
        my $lastLine      = $baseLine;
      INDENT: for my $ix ( 1 .. $#$indents ) {
            my $indent = $indents->[$ix];
            my ( $thisLine, $thisColumn ) = @{$indent};
            $currentIndent -= 2;

            # say "$currentIndent vs. $thisColumn";
            next INDENT if $thisLine == $lastLine;
            if ( $currentIndent != $thisColumn ) {
                my $msg = sprintf
                  "Child #%d @ line %d; backdent is %d; should be %d",
                  $ix, $thisLine, $thisColumn, $currentIndent;
                push @mistakes,
                  {
                    desc           => $msg,
                    line           => $thisLine,
                    column         => $thisColumn,
                    child          => $ix,
                    backdentColumn => $currentIndent,
                  };
            }
            $lastLine = $thisLine;
        }
        return \@mistakes;
    }

    # By default, report anomalies in terms of differences from backdenting
    # to the rule start.
    sub defaultMistakes {
        my ( $indents, $type ) = @_;
        my $mistakes = isBackdented($indents);
        return [ { desc => "Undetected mistakes" } ]
          if not @{$mistakes};
        for my $mistake ( @{$mistakes} ) {
            my $mistakeChild  = $mistake->{child};
            my $mistakeColumn = $mistake->{column};
            my $defaultColumn = $mistake->{backdentColumn};
            my $mistakeLine   = $mistake->{line};
            my $msg           = sprintf
              "$type child #%d; line %d; indent=%d vs. default of %d",
              $mistakeChild, $mistakeLine, $mistakeColumn,
              $defaultColumn;
            $mistake->{desc} = $msg;
        }
        return $mistakes;
    }

    sub isFlat {
        my ($indents)   = @_;
        my ($firstLine) = @{ $indents->[0] };
        my ($lastLine)  = @{ $indents->[$#$indents] };
        return $firstLine == $lastLine;
    }

    my $displayMistakes = sub {

        # say join " ", __FILE__, __LINE__, "displayMistakes()";
        my ( $mistakes, $hoonDesc ) = @_;
        my $parentLC = join ':', $parentLine, $parentColumn + 1;
        my @pieces = ();
      MISTAKE: for my $mistake ( @{$mistakes} ) {

            # say join " ", __FILE__, __LINE__, "displayMistakes()";
            my $type = $mistake->{type};
            next MISTAKE
              if $inclusions and not $inclusions->{$type}{$parentLC};

            my $desc              = $mistake->{desc};
            my $mistakeLine       = $mistake->{line};
            my $mistakeTopicLines = $mistake->{topicLines};
            my @topicLines        = ($parentLine);
            push @topicLines, @{$mistakeTopicLines} if $mistakeTopicLines;

            reportItem( ("$fileName $parentLC $type $hoonDesc $desc"),
                \@topicLines, $mistakeLine, );
        }
    };

    # say STDERR __LINE__, " parentIndents: ", (join " ", @parentIndents);
    # if here, gapiness > 0
    {
        my $mistakes = [];
        my $start    = $node->{start};

        my $indentDesc = '???';

        my @gapIndents = @{ calcGapIndents($node) };

      TYPE_INDENT: {

            my $suppression = $suppressions->{'indent'}{$parentLC};
            if ( defined $suppression ) {
                $indentDesc = "SUPPRESSION $suppression";
                $unusedSuppressions->{'indent'}{$parentLC} = undef;
                last TYPE_INDENT;
            }

            if ( $tallJogRule->{$lhsName} ) {
                $mistakes = $isJog->( $node, $parentContext );
                last TYPE_INDENT if @{$mistakes};
                $indentDesc = 'JOG-STYLE';
                last TYPE_INDENT;
            }

            # if ( isFlat( \@gapIndents ) ) {
            # $indentDesc = 'FLAT';
            # last TYPE_INDENT;
            # }

            if ( $tall_0JoggingRule->{$lhsName} ) {
                $mistakes =
                  is_0Jogging( $parentLine, $parentColumn, \@gapIndents );
                last TYPE_INDENT if @{$mistakes};
                $indentDesc = 'JOGGING-0-STYLE';
                last TYPE_INDENT;
            }

            if ( $tall_1JoggingRule->{$lhsName} ) {
                $mistakes =
                  $isJogging1->( $parentContext, $node, \@gapIndents );
                last TYPE_INDENT if @{$mistakes};
                $indentDesc = 'JOGGING-1-STYLE';
                last TYPE_INDENT;
            }

            if ( $tall_2JoggingRule->{$lhsName} ) {
                $mistakes =
                  $isJogging2->( $parentContext, $node, \@gapIndents );
                last TYPE_INDENT if @{$mistakes};
                $indentDesc = 'JOGGING-2-STYLE';
                last TYPE_INDENT;
            }

            if ( $tallJogging1_Rule->{$lhsName} ) {
                $mistakes =
                  $isJogging_1->( $parentContext, $node, \@gapIndents );
                last TYPE_INDENT if @{$mistakes};
                $indentDesc = 'JOGGING-PREFIX-STYLE';
                last TYPE_INDENT;
            }

            if ( $tallNoteRule->{$lhsName} ) {
                $mistakes = isBackdented( \@gapIndents, $noteIndent );
                last TYPE_INDENT if @{$mistakes};
                $indentDesc = 'CAST-STYLE';
                last TYPE_INDENT;
            }

            if ( $tallLuslusRule->{$lhsName} ) {
                $mistakes = isLuslusStyle( \@gapIndents );
                last TYPE_INDENT if @{$mistakes};
                $indentDesc = 'LUSLUS-STYLE';
                last TYPE_INDENT;
            }

            # By default, treat as backdented
            $mistakes = isBackdented( \@gapIndents );
            if ( not @{$mistakes} ) {
                $indentDesc = 'BACKDENTED';
                last TYPE_INDENT;
            }

        }

      PRINT: {
          # say join " ", __FILE__, __LINE__, "$lhsName", (scalar @{$mistakes});
            if ( @{$mistakes} ) {
                $_->{type} = 'indent' for @{$mistakes};
                $displayMistakes->(
                    $mistakes, diagName( $node, $parentContext )
                );
                last PRINT;
            }

            if ($censusWhitespace) {
                reportItem(
                    (
                        sprintf "$fileName %s indent %s %s",
                        ( join ':', $recce->line_column($start) ),
                        diagName( $node, $parentContext ),
                        $indentDesc
                    ),
                    $parentLine,
                    $parentLine
                );
            }
        }
    }
  CHILD: for my $childIX ( 0 .. $#$children ) {
        my $child = $children->[$childIX];
        $policy->validate( $instance, $child, $parentContext );
    }
}
