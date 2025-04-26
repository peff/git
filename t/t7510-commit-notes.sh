#!/bin/sh

test_description='commit w/ --notes'
. ./test-lib.sh

# Fake editor to simulate user adding a note.
cat >add.sh <<'EOF'
perl -i -pe '
  BEGIN { $n = shift }
  # insert at $n-th blank line
  if (/^$/ && ++$count == $n) {
	  print "---\n";
	  print "added note\n";
	  print "with multiple lines\n";
  }
' "$@"
EOF
cat >expect-add <<'EOF'
added note
with multiple lines
EOF

# Fake editor to simulate user deleting a note.
cat >del.sh <<'EOF'
perl -i -ne '
  if (/^---$/) {
	  while (<>) {
		  last if /^$/;
	  }
	  next;
  }
  print;
' "$1"
EOF

# Fake editor to simulate user modifying a note.
cat >mod.sh <<'EOF'
perl -i -pe '
  s/added note/modified note/
' "$1"
EOF
cat >expect-mod <<'EOF'
modified note
with multiple lines
EOF

# Fake editor for leaving notes untouched.
cat >nil.sh <<'EOF'
EOF

# Convenience function for setting up editor.
set_editor() {
	git config core.editor "\"$SHELL_PATH\" $1.sh $2"
}

cat >expect-msg <<'EOF'
commit one

this is the body of commit one
EOF

test_expect_success 'setup' '
	test_commit one &&
	git commit --amend -F expect-msg
'

test_expect_success 'add a note' '
	set_editor add 2 &&
	git commit --notes --amend &&
	git notes show >actual &&
	test_cmp expect-add actual &&
	git log -1 --pretty=format:%B >actual &&
	test_cmp expect-msg actual
'

test_expect_success 'notes are preserved' '
	set_editor nil &&
	git commit --notes --amend &&
	git notes show >actual &&
	test_cmp expect-add actual &&
	git log -1 --pretty=format:%B >actual &&
	test_cmp expect-msg actual
'

test_expect_success 'modify a note' '
	set_editor mod &&
	git commit --notes --amend &&
	git notes show >actual &&
	test_cmp expect-mod actual &&
	git log -1 --pretty=format:%B >actual &&
	test_cmp expect-msg actual
'

test_expect_success 'delete a note' '
	set_editor del &&
	git commit --notes --amend &&
	test_must_fail git notes show &&
	git log -1 --pretty=format:%B >actual &&
	test_cmp expect-msg actual
'

test_expect_success 'add to commit without body' '
	test_commit two &&
	git log -1 --pretty=format:%B >expect-msg &&
	set_editor add 1 &&
	git commit --notes --amend &&
	git notes show >actual &&
	test_cmp expect-add actual &&
	git log -1 --pretty=format:%B >actual &&
	test_cmp expect-msg actual
'

cat >expect-verbatim-msg <<'EOF'
verbatim subject

verbatim body
# embedded comment

EOF
cat >expect-verbatim-note <<'EOF'

verbatim note
with leading and trailing whitespace
# and embedded comments

EOF
cat >verbatim.sh <<'EOF'
{
	cat expect-verbatim-msg &&
	echo --- &&
	cat expect-verbatim-note
} >"$1"
EOF

test_expect_success 'commit --cleanup=verbatim preserves message and notes' '
	test_tick &&
	echo content >>file && git add file &&
	set_editor verbatim &&
	git commit --notes --cleanup=verbatim &&
	git cat-file commit HEAD >msg.raw &&
	sed "1,/^\$/d" <msg.raw >actual &&
	test_cmp expect-verbatim-msg actual &&
	git notes show >actual &&
	test_cmp expect-verbatim-note actual
'

test_expect_success 'commit -v does not interfere with notes' '
	test_commit three &&
	git log -1 --pretty=format:%B >expect-msg
	set_editor add 1 &&
	git commit -v --notes --amend &&
	git notes show >actual &&
	test_cmp actual expect-add &&
	git log -1 --pretty=format:%B >actual &&
	test_cmp expect-msg actual
'

test_expect_success 'edit notes on alternate ref' '
	test_commit four &&
	set_editor add 1 &&
	git commit --notes=foo --amend &&
	test_must_fail git notes show &&
	git notes --ref refs/notes/foo show >actual &&
	test_cmp expect-add actual
'

test_expect_success 'ref rewriting does not overwrite our edits' '
	git config notes.rewriteRef refs/notes/commits &&
	test_commit five &&
	set_editor add 1 &&
	git commit --notes --amend &&
	git notes show >actual &&
	test_cmp expect-add actual &&
	set_editor mod &&
	git commit --notes --amend &&
	git notes show >actual &&
	test_cmp expect-mod actual &&
	set_editor del &&
	git commit --notes --amend &&
	test_must_fail git notes show
'

test_done
