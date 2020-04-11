GIT_SEND_EMAIL_NOTTY=1
export GIT_SEND_EMAIL_NOTTY

replace_variable_fields () {
	sed	-e "s/^\(Date:\).*/\1 DATE-STRING/" \
		-e "s/^\(Message-Id:\).*/\1 MESSAGE-ID-STRING/" \
		-e "s/^\(X-Mailer:\).*/\1 X-MAILER-STRING/"
}

clean_fake_sendmail () {
	rm -f commandline* msgtxt*
}

test_expect_success PERL 'prepare reference tree' '
	echo "1A quick brown fox jumps over the" >file &&
	echo "lazy dog" >>file &&
	git add file &&
	GIT_AUTHOR_NAME="A" git commit -a -m "Initial."
'

test_expect_success PERL 'Setup helper tool' '
	write_script fake.sendmail <<-\EOF &&
	shift
	output=1
	while test -f commandline$output
	do
		output=$(($output+1))
	done
	for a
	do
		echo "!$a!"
	done >commandline$output
	cat >"msgtxt$output"
	EOF
	git add fake.sendmail &&
	GIT_AUTHOR_NAME="A" git commit -a -m "Second."
'

test_expect_success PERL 'Extract patches' '
	patches=$(git format-patch -s --cc="One <one@example.com>" --cc=two@example.com -n HEAD^1) &&
	threaded_patches=$(git format-patch -o threaded -s --in-reply-to="format" HEAD^1)
'

test_expect_success PERL 'setup fake editor' '
	write_script fake-editor <<-\EOF
	echo fake edit >>"$1"
	EOF
'

test_set_editor "$(pwd)/fake-editor"

test_expect_success PERL 'setup tocmd and cccmd scripts' '
	write_script tocmd-sed <<-\EOF &&
	sed -n -e "s/^tocmd--//p" "$1"
	EOF
	write_script cccmd-sed <<-\EOF
	sed -n -e "s/^cccmd--//p" "$1"
	EOF
'
