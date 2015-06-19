package DiffHighlight;

use 5.008001;
use warnings FATAL => 'all';
use strict;
use Algorithm::Diff;

# Use the correct value for both UNIX and Windows (/dev/null vs nul)
use File::Spec;

my $NULL = File::Spec->devnull();

# Highlight by reversing foreground and background. You could do
# other things like bold or underline if you prefer.
my @OLD_HIGHLIGHT = (
	color_config('color.diff-highlight.oldnormal'),
	color_config('color.diff-highlight.oldhighlight', "\x1b[7m"),
	color_config('color.diff-highlight.oldreset', "\x1b[27m")
);
my @NEW_HIGHLIGHT = (
	color_config('color.diff-highlight.newnormal', $OLD_HIGHLIGHT[0]),
	color_config('color.diff-highlight.newhighlight', $OLD_HIGHLIGHT[1]),
	color_config('color.diff-highlight.newreset', $OLD_HIGHLIGHT[2])
);

my $RESET = "\x1b[m";
my $COLOR = qr/\x1b\[[0-9;]*m/;
my $BORING = qr/$COLOR|\s/;

my @removed;
my @added;
my $in_hunk;
my $graph_indent = 0;

our $line_cb = sub { print @_ };
our $flush_cb = sub { local $| = 1 };

# Count the visible width of a string, excluding any terminal color sequences.
sub visible_width {
	local $_ = shift;
	my $ret = 0;
	while (length) {
		if (s/^$COLOR//) {
			# skip colors
		} elsif (s/^.//) {
			$ret++;
		}
	}
	return $ret;
}

# Return a substring of $str, omitting $len visible characters from the
# beginning, where terminal color sequences do not count as visible.
sub visible_substr {
	my ($str, $len) = @_;
	while ($len > 0) {
		if ($str =~ s/^$COLOR//) {
			next
		}
		$str =~ s/^.//;
		$len--;
	}
	return $str;
}

sub handle_line {
	my $orig = shift;
	local $_ = $orig;

	# match a graph line that begins a commit
	if (/^(?:$COLOR?\|$COLOR?[ ])* # zero or more leading "|" with space
	         $COLOR?\*$COLOR?[ ]   # a "*" with its trailing space
	      (?:$COLOR?\|$COLOR?[ ])* # zero or more trailing "|"
	                         [ ]*  # trailing whitespace for merges
	    /x) {
		my $graph_prefix = $&;

		# We must flush before setting graph indent, since the
		# new commit may be indented differently from what we
		# queued.
		flush();
		$graph_indent = visible_width($graph_prefix);

	} elsif ($graph_indent) {
		if (length($_) < $graph_indent) {
			$graph_indent = 0;
		} else {
			$_ = visible_substr($_, $graph_indent);
		}
	}

	if (!$in_hunk) {
		$line_cb->($orig);
		$in_hunk = /^$COLOR*\@\@ /;
	}
	elsif (/^$COLOR*-/) {
		push @removed, $orig;
	}
	elsif (/^$COLOR*\+/) {
		push @added, $orig;
	}
	else {
		flush();
		$line_cb->($orig);
		$in_hunk = /^$COLOR*[\@ ]/;
	}

	# Most of the time there is enough output to keep things streaming,
	# but for something like "git log -Sfoo", you can get one early
	# commit and then many seconds of nothing. We want to show
	# that one commit as soon as possible.
	#
	# Since we can receive arbitrary input, there's no optimal
	# place to flush. Flushing on a blank line is a heuristic that
	# happens to match git-log output.
	if (/^$/) {
		$flush_cb->();
	}
}

sub flush {
	# Flush any queued hunk (this can happen when there is no trailing
	# context in the final diff of the input).
	show_hunk(\@removed, \@added);
	@removed = ();
	@added = ();
}

sub highlight_stdin {
	while (<STDIN>) {
		handle_line($_);
	}
	flush();
}

# Ideally we would feed the default as a human-readable color to
# git-config as the fallback value. But diff-highlight does
# not otherwise depend on git at all, and there are reports
# of it being used in other settings. Let's handle our own
# fallback, which means we will work even if git can't be run.
sub color_config {
	my ($key, $default) = @_;
	my $s = `git config --get-color $key 2>$NULL`;
	return length($s) ? $s : $default;
}

sub show_hunk {
	my ($lines_a, $lines_b) = @_;

	# If one side is empty, then there is nothing to compare or highlight.
	if (!@$lines_a || !@$lines_b) {
		$line_cb->(@$lines_a, @$lines_b);
		return;
	}

	# Strip out any cruft so we can do the real diff on $a and $b.
	my ($a, @stripped_a) = strip_image(@$lines_a);
	my ($b, @stripped_b) = strip_image(@$lines_b);

	# Now we do the actual diff. Our highlight list is in the same
	# annotation format as the @stripped data.
	my $diff = Algorithm::Diff->new([split_image($a)], [split_image($b)]);
	my ($offset_a, $offset_b) = (0, 0);
	my (@highlight_a, @highlight_b);
	while ($diff->Next()) {
		my $bits = $diff->Diff();

		push @highlight_a, [$offset_a, $OLD_HIGHLIGHT[1]]
			if $bits & 1;
		$offset_a += length($_) for $diff->Items(1);
		push @highlight_a, [$offset_a, $OLD_HIGHLIGHT[2]]
			if $bits & 1;

		push @highlight_b, [$offset_b, $NEW_HIGHLIGHT[1]]
			if $bits & 2;
		$offset_b += length($_) for $diff->Items(2);
		push @highlight_b, [$offset_b, $NEW_HIGHLIGHT[2]]
			if $bits & 2;
	}

	# And now show the output both with the original stripped annotations,
	# as well as our new highlights.
	show_image($a, [merge_annotations(\@stripped_a, \@highlight_a)]);
	show_image($b, [merge_annotations(\@stripped_b, \@highlight_b)]);
}

# Strip out any diff syntax (i.e., leading +/-), along with any ANSI color
# codes from the pre- or post-image of a hunk. The result is a string of text
# suitable for diffing against the other side of the hunk.
#
# In addition to returning the hunk itself, we also return an arrayref that
# contains the stripped data.  Each element is itself an arrayref containing
# the offset into the stripped hunk, along with the stripped data that belongs
# there.
sub strip_image {
	my $image = '';
	my @stripped;
	foreach my $line (@_) {
		$line =~ s/^$COLOR*[+-]$COLOR*//
			or die "BUG: line was not +/-: $line";
		push @stripped, [length($image), $&];

		while (length($line)) {
			if ($line =~ s/^$COLOR+//) {
				push @stripped, [length($image), $&];
			} elsif ($line =~ s/^(.+?)($COLOR|$)/$2/s) {
				$image .= $1;
			} else {
				die "BUG: we should have matched _something_";
			}
		}
	}

	return $image, @stripped;
}

# Split the pre- or post-image into diffable elements. Returns
sub split_image {
	return split(/([[:space:]]+|[[:punct:]]+)/, shift);
}

sub merge_annotations {
	my ($a, $b) = @_;
	my @r;
	while (@$a && @$b) {
		if ($a->[0]->[0] <= $b->[0]->[0]) {
			push @r, shift @$a;
		} else {
			push @r, shift @$b;
		}
	}
	push @r, @$a;
	push @r, @$b;
	return @r;
}

sub show_image {
	my ($image, $annotations) = @_;
	my $pos = 0;

	foreach my $an (@$annotations) {
		if ($pos < $an->[0]) {
			$line_cb->(substr($image, $pos, $an->[0] - $pos));
			$pos = $an->[0];
		}
		$line_cb->($an->[1]);
	}

	if ($pos < length($image)) {
		$line_cb->(substr($image, $pos));
	}
}
