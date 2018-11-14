use strict;
use warnings;
use Data::Dumper;
use FindBin;
use IO::Scalar;
use MIME::Base64;
use Test::Exception;
use Test::More tests => 43;

use lib ( "$FindBin::Bin/../lib", "$FindBin::Bin/lib" );
use Validate::JSONPath;

my %entries;
$entries{'$.phoneNumbers[:1].type'} = 1; # GOOD
$entries{'$.phoneNumbers'} = 1; # GOOD
$entries{'$.phone[0]'} = 1; # GOOD
$entries{'$.boop()'} = 1; # GOOD
$entries{'$.a b c.def'} = 0; # bracket notation required

$entries{'$.'} = 0; # GOOD ERROR
$entries{'$.boop(123, "abc", "3)'} = 0; # GOOD ERROR

$entries{'$.boop(1, 2, "3")'} = 1; # GOOD
$entries{'$.boop(123, "abc", "3")'} = 1; # GOOD
$entries{'$.phoneNumbers.stuff.foo'} = 1; # GOOD
$entries{'$.e["4"]'} = 1;
$entries{'$.e["4"].foo()'} = 1;

$entries{'$..book[2].title'} = 1;
$entries{'$.store.book[1].not_there'} = 1;
$entries{'$.store.book[*].author'} = 1;

$entries{'totally-crap'} = 0;
$entries{'$[}'} = 0;
$entries{'$..*'} = 1; # GOOD, but sheesh the syntax here is freaking awful!
$entries{'$..book[2].title'} = 1;
$entries{'$bad'} = 0;
$entries{"\$.store.bicycle[?(@.color == 'red' )]"} = 1;
$entries{"\$.['store'].['book'][0]"} = 1;
$entries{"\$.['s t o r e'].book[0]"} = 1;
$entries{'$..book[0]'} = 1;
$entries{'$.store.book[?(!@.isbn)]'} = 1;
$entries{'$.store.book[0:2]'} = 1;
$entries{'$.store.book[0:X]'} = 0;
$entries{"\$.store.book[*]['author', 'isbn']"} = 1;
$entries{"\$.store.book[*]['author', 'isbn', 23]"} = 0;
$entries{"\$.[?(@.foo in ['bar'])].foo"} = 1;
$entries{"\$..['a'].x"} = 1;
$entries{'$.batches.results[?(@.values.length() >= $.batches.minBatchSize)].values.avg()'} = 1;
$entries{'$.foo['} = 0;
$entries{'$.foo('} = 0;
$entries{'$.foo.'} = 0;
$entries{'$.numbers.append(11, 12, "abc")'} = 1;
$entries{'$.numbers.append(11, 12, abc")'} = 0;
$entries{'$.numbers.append(11, 12, abc(1, "moo")'} = 0;
$entries{'$.numbers.append(11, 12, abc(1, "moo"))'} = 1;
$entries{'$.store.book[?].category'} = 1; # Ugh, don't have predicates, but this is still valid technically
$entries{'$.logs[?(@.message && (@.id == 1 || @.id == 2))].id'} = 1;
$entries{'$.abc[*,]'} = 0;
$entries{"\$.p.['s', 't'].u"} = 1;
$entries{"\$.p.['s', \"t\"].u"} = 0; # XXX not sure this is invalid but jayway doesn't like it

foreach my $entry ( sort(keys(%entries)) ) {
    my $res;
    eval {
        my Validate::JSONPath $jp = Validate::JSONPath->new($entry);
        $res = $jp->verify($entry);
    };
    if ( $@ ) {
        ok( ! $entries{$entry}, "failure -- $entry");
        if ( $entries{$entry} ) {
            print $@ . "\n";
        }
    } else {
        ok( $entries{$entry},   "success -- $entry");
    }
}
