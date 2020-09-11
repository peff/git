#!/bin/sh

test_description='git send-email'
. ./test-lib.sh
. "$TEST_DIRECTORY/lib-send-email.sh"

test_expect_success PERL 'Send patches' '
	git send-email --suppress-cc=sob --from="Example <nobody@example.com>" --to=nobody@example.com --smtp-server="$(pwd)/fake.sendmail" $patches 2>errors
'

test_expect_success PERL 'setup expect' '
	cat >expected <<-\EOF
	!nobody@example.com!
	!author@example.com!
	!one@example.com!
	!two@example.com!
	EOF
'

test_expect_success PERL 'Verify commandline' '
	test_cmp expected commandline1
'

test_expect_success PERL 'Send patches with --envelope-sender' '
	clean_fake_sendmail &&
	git send-email --envelope-sender="Patch Contributor <patch@example.com>" --suppress-cc=sob --from="Example <nobody@example.com>" --to=nobody@example.com --smtp-server="$(pwd)/fake.sendmail" $patches 2>errors
'

test_expect_success PERL 'setup expect' '
	cat >expected <<-\EOF
	!patch@example.com!
	!-i!
	!nobody@example.com!
	!author@example.com!
	!one@example.com!
	!two@example.com!
	EOF
'

test_expect_success PERL 'Verify commandline' '
	test_cmp expected commandline1
'

test_expect_success PERL 'Send patches with --envelope-sender=auto' '
	clean_fake_sendmail &&
	git send-email --envelope-sender=auto --suppress-cc=sob --from="Example <nobody@example.com>" --to=nobody@example.com --smtp-server="$(pwd)/fake.sendmail" $patches 2>errors
'

test_expect_success PERL 'setup expect' '
	cat >expected <<-\EOF
	!nobody@example.com!
	!-i!
	!nobody@example.com!
	!author@example.com!
	!one@example.com!
	!two@example.com!
	EOF
'

test_expect_success PERL 'Verify commandline' '
	test_cmp expected commandline1
'

test_expect_success PERL 'setup expect for cc trailer' "
cat >expected-cc <<\EOF
!recipient@example.com!
!author@example.com!
!one@example.com!
!two@example.com!
!three@example.com!
!four@example.com!
!five@example.com!
!six@example.com!
EOF
"

test_expect_success PERL 'cc trailer with various syntax' '
	test_commit cc-trailer &&
	test_when_finished "git reset --hard HEAD^" &&
	git commit --amend -F - <<-EOF &&
	Test Cc: trailers.

	Cc: one@example.com
	Cc: <two@example.com> # trailing comments are ignored
	Cc: <three@example.com>, <not.four@example.com> one address per line
	Cc: "Some # Body" <four@example.com> [ <also.a.comment> ]
	Cc: five@example.com # not.six@example.com
	Cc: six@example.com, not.seven@example.com
	EOF
	clean_fake_sendmail &&
	git send-email -1 --to=recipient@example.com \
		--smtp-server="$(pwd)/fake.sendmail" &&
	test_cmp expected-cc commandline1
'

test_expect_success PERL 'setup fake get_maintainer.pl script for cc trailer' "
	write_script expected-cc-script.sh <<-EOF
	echo 'One Person <one@example.com> (supporter:THIS (FOO/bar))'
	echo 'Two Person <two@example.com> (maintainer:THIS THING)'
	echo 'Third List <three@example.com> (moderated list:THIS THING (FOO/bar))'
	echo '<four@example.com> (moderated list:FOR THING)'
	echo 'five@example.com (open list:FOR THING (FOO/bar))'
	echo 'six@example.com (open list)'
	EOF
"

test_expect_success PERL 'cc trailer with get_maintainer.pl output' '
	clean_fake_sendmail &&
	git send-email -1 --to=recipient@example.com \
		--cc-cmd=./expected-cc-script.sh \
		--smtp-server="$(pwd)/fake.sendmail" &&
	test_cmp expected-cc commandline1
'

test_expect_success PERL 'setup expect' "
cat >expected-show-all-headers <<\EOF
0001-Second.patch
(mbox) Adding cc: A <author@example.com> from line 'From: A <author@example.com>'
(mbox) Adding cc: One <one@example.com> from line 'Cc: One <one@example.com>, two@example.com'
(mbox) Adding cc: two@example.com from line 'Cc: One <one@example.com>, two@example.com'
Dry-OK. Log says:
Server: relay.example.com
MAIL FROM:<from@example.com>
RCPT TO:<to@example.com>
RCPT TO:<cc@example.com>
RCPT TO:<author@example.com>
RCPT TO:<one@example.com>
RCPT TO:<two@example.com>
RCPT TO:<bcc@example.com>
From: Example <from@example.com>
To: to@example.com
Cc: cc@example.com,
	A <author@example.com>,
	One <one@example.com>,
	two@example.com
Subject: [PATCH 1/1] Second.
Date: DATE-STRING
Message-Id: MESSAGE-ID-STRING
X-Mailer: X-MAILER-STRING
In-Reply-To: <unique-message-id@example.com>
References: <unique-message-id@example.com>
Reply-To: Reply <reply@example.com>
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit

Result: OK
EOF
"

test_suppress_self () {
	test_commit $3 &&
	test_when_finished "git reset --hard HEAD^" &&

	write_script cccmd-sed <<-EOF &&
		sed -n -e s/^cccmd--//p "\$1"
	EOF

	git commit --amend --author="$1 <$2>" -F - &&
	clean_fake_sendmail &&
	git format-patch --stdout -1 >"suppress-self-$3.patch" &&

	git send-email --from="$1 <$2>" \
		--to=nobody@example.com \
		--cc-cmd=./cccmd-sed \
		--suppress-cc=self \
		--smtp-server="$(pwd)/fake.sendmail" \
		suppress-self-$3.patch &&

	mv msgtxt1 msgtxt1-$3 &&
	sed -e '/^$/q' msgtxt1-$3 >"msghdr1-$3" &&

	(grep '^Cc:' msghdr1-$3 >"actual-no-cc-$3";
	 test_must_be_empty actual-no-cc-$3)
}

test_suppress_self_unquoted () {
	test_suppress_self "$1" "$2" "unquoted-$3" <<-EOF
		test suppress-cc.self unquoted-$3 with name $1 email $2

		unquoted-$3

		cccmd--$1 <$2>

		Cc: $1 <$2>
		Signed-off-by: $1 <$2>
	EOF
}

test_suppress_self_quoted () {
	test_suppress_self "$1" "$2" "quoted-$3" <<-EOF
		test suppress-cc.self quoted-$3 with name $1 email $2

		quoted-$3

		cccmd--"$1" <$2>

		Cc: $1 <$2>
		Cc: "$1" <$2>
		Signed-off-by: $1 <$2>
		Signed-off-by: "$1" <$2>
	EOF
}

test_expect_success PERL 'self name is suppressed' "
	test_suppress_self_unquoted 'A U Thor' 'author@example.com' \
		'self_name_suppressed'
"

test_expect_success PERL 'self name with dot is suppressed' "
	test_suppress_self_quoted 'A U. Thor' 'author@example.com' \
		'self_name_dot_suppressed'
"

test_expect_success PERL 'non-ascii self name is suppressed' "
	test_suppress_self_quoted 'Füñný Nâmé' 'odd_?=mail@example.com' \
		'non_ascii_self_suppressed'
"

# This name is long enough to force format-patch to split it into multiple
# encoded-words, assuming it uses UTF-8 with the "Q" encoding.
test_expect_success PERL 'long non-ascii self name is suppressed' "
	test_suppress_self_quoted 'Ƒüñníęř €. Nâṁé' 'odd_?=mail@example.com' \
		'long_non_ascii_self_suppressed'
"

test_expect_success PERL 'sanitized self name is suppressed' "
	test_suppress_self_unquoted '\"A U. Thor\"' 'author@example.com' \
		'self_name_sanitized_suppressed'
"

test_expect_success PERL 'Show all headers' '
	git send-email \
		--dry-run \
		--suppress-cc=sob \
		--from="Example <from@example.com>" \
		--reply-to="Reply <reply@example.com>" \
		--to=to@example.com \
		--cc=cc@example.com \
		--bcc=bcc@example.com \
		--in-reply-to="<unique-message-id@example.com>" \
		--smtp-server relay.example.com \
		$patches | replace_variable_fields \
		>actual-show-all-headers &&
	test_cmp expected-show-all-headers actual-show-all-headers
'

test_expect_success PERL 'Prompting works' '
	clean_fake_sendmail &&
	(echo "to@example.com" &&
	 echo ""
	) | git send-email \
		--smtp-server="$(pwd)/fake.sendmail" \
		$patches \
		2>errors &&
		grep "^From: A U Thor <author@example.com>\$" msgtxt1 &&
		grep "^To: to@example.com\$" msgtxt1
'

test_expect_success PERL,AUTOIDENT 'implicit ident is allowed' '
	clean_fake_sendmail &&
	(sane_unset GIT_AUTHOR_NAME &&
	sane_unset GIT_AUTHOR_EMAIL &&
	sane_unset GIT_COMMITTER_NAME &&
	sane_unset GIT_COMMITTER_EMAIL &&
	git send-email \
		--smtp-server="$(pwd)/fake.sendmail" \
		--to=to@example.com \
		$patches </dev/null 2>errors
	)
'

test_expect_success PERL,!AUTOIDENT 'broken implicit ident aborts send-email' '
	clean_fake_sendmail &&
	(sane_unset GIT_AUTHOR_NAME &&
	sane_unset GIT_AUTHOR_EMAIL &&
	sane_unset GIT_COMMITTER_NAME &&
	sane_unset GIT_COMMITTER_EMAIL &&
	test_must_fail git send-email \
		--smtp-server="$(pwd)/fake.sendmail" \
		--to=to@example.com \
		$patches </dev/null 2>errors &&
	test_i18ngrep "tell me who you are" errors
	)
'

test_expect_success PERL 'tocmd works' '
	clean_fake_sendmail &&
	cp $patches tocmd.patch &&
	echo tocmd--tocmd@example.com >>tocmd.patch &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to-cmd=./tocmd-sed \
		--smtp-server="$(pwd)/fake.sendmail" \
		tocmd.patch \
		&&
	grep "^To: tocmd@example.com" msgtxt1
'

test_expect_success PERL 'cccmd works' '
	clean_fake_sendmail &&
	cp $patches cccmd.patch &&
	echo "cccmd--  cccmd@example.com" >>cccmd.patch &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--cc-cmd=./cccmd-sed \
		--smtp-server="$(pwd)/fake.sendmail" \
		cccmd.patch \
		&&
	grep "^	cccmd@example.com" msgtxt1
'

test_expect_success PERL 'reject long lines' '
	z8=zzzzzzzz &&
	z64=$z8$z8$z8$z8$z8$z8$z8$z8 &&
	z512=$z64$z64$z64$z64$z64$z64$z64$z64 &&
	clean_fake_sendmail &&
	cp $patches longline.patch &&
	echo $z512$z512 >>longline.patch &&
	test_must_fail git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--transfer-encoding=8bit \
		$patches longline.patch \
		2>errors &&
	grep longline.patch errors
'

test_expect_success PERL 'no patch was sent' '
	! test -e commandline1
'

test_expect_success PERL 'Author From: in message body' '
	clean_fake_sendmail &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		$patches &&
	sed "1,/^\$/d" <msgtxt1 >msgbody1 &&
	grep "From: A <author@example.com>" msgbody1
'

test_expect_success PERL 'Author From: not in message body' '
	clean_fake_sendmail &&
	git send-email \
		--from="A <author@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		$patches &&
	sed "1,/^\$/d" <msgtxt1 >msgbody1 &&
	! grep "From: A <author@example.com>" msgbody1
'

test_expect_success PERL 'allow long lines with --no-validate' '
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--no-validate \
		$patches longline.patch \
		2>errors
'

test_expect_success PERL 'short lines with auto encoding are 8bit' '
	clean_fake_sendmail &&
	git send-email \
		--from="A <author@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--transfer-encoding=auto \
		$patches &&
	grep "Content-Transfer-Encoding: 8bit" msgtxt1
'

test_expect_success PERL 'long lines with auto encoding are quoted-printable' '
	clean_fake_sendmail &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--transfer-encoding=auto \
		--no-validate \
		longline.patch &&
	grep "Content-Transfer-Encoding: quoted-printable" msgtxt1
'

test_expect_success PERL 'carriage returns with auto encoding are quoted-printable' '
	clean_fake_sendmail &&
	cp $patches cr.patch &&
	printf "this is a line\r\n" >>cr.patch &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--transfer-encoding=auto \
		--no-validate \
		cr.patch &&
	grep "Content-Transfer-Encoding: quoted-printable" msgtxt1
'

for enc in auto quoted-printable base64
do
	test_expect_success PERL "--validate passes with encoding $enc" '
		git send-email \
			--from="Example <nobody@example.com>" \
			--to=nobody@example.com \
			--smtp-server="$(pwd)/fake.sendmail" \
			--transfer-encoding=$enc \
			--validate \
			$patches longline.patch
	'

done

for enc in 7bit 8bit quoted-printable base64
do
	test_expect_success PERL "--transfer-encoding=$enc produces correct header" '
		clean_fake_sendmail &&
		git send-email \
			--from="Example <nobody@example.com>" \
			--to=nobody@example.com \
			--smtp-server="$(pwd)/fake.sendmail" \
			--transfer-encoding=$enc \
			$patches &&
		grep "Content-Transfer-Encoding: $enc" msgtxt1
	'
done

test_expect_success PERL 'Invalid In-Reply-To' '
	clean_fake_sendmail &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--in-reply-to=" " \
		--smtp-server="$(pwd)/fake.sendmail" \
		$patches \
		2>errors &&
	! grep "^In-Reply-To: < *>" msgtxt1
'

test_expect_success PERL 'Valid In-Reply-To when prompting' '
	clean_fake_sendmail &&
	(echo "From Example <from@example.com>" &&
	 echo "To Example <to@example.com>" &&
	 echo ""
	) | git send-email \
		--smtp-server="$(pwd)/fake.sendmail" \
		$patches 2>errors &&
	! grep "^In-Reply-To: < *>" msgtxt1
'

test_expect_success PERL 'In-Reply-To without --chain-reply-to' '
	clean_fake_sendmail &&
	echo "<unique-message-id@example.com>" >expect &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--no-chain-reply-to \
		--in-reply-to="$(cat expect)" \
		--smtp-server="$(pwd)/fake.sendmail" \
		$patches $patches $patches \
		2>errors &&
	# The first message is a reply to --in-reply-to
	sed -n -e "s/^In-Reply-To: *\(.*\)/\1/p" msgtxt1 >actual &&
	test_cmp expect actual &&
	# Second and subsequent messages are replies to the first one
	sed -n -e "s/^Message-Id: *\(.*\)/\1/p" msgtxt1 >expect &&
	sed -n -e "s/^In-Reply-To: *\(.*\)/\1/p" msgtxt2 >actual &&
	test_cmp expect actual &&
	sed -n -e "s/^In-Reply-To: *\(.*\)/\1/p" msgtxt3 >actual &&
	test_cmp expect actual
'

test_expect_success PERL 'In-Reply-To with --chain-reply-to' '
	clean_fake_sendmail &&
	echo "<unique-message-id@example.com>" >expect &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--chain-reply-to \
		--in-reply-to="$(cat expect)" \
		--smtp-server="$(pwd)/fake.sendmail" \
		$patches $patches $patches \
		2>errors &&
	sed -n -e "s/^In-Reply-To: *\(.*\)/\1/p" msgtxt1 >actual &&
	test_cmp expect actual &&
	sed -n -e "s/^Message-Id: *\(.*\)/\1/p" msgtxt1 >expect &&
	sed -n -e "s/^In-Reply-To: *\(.*\)/\1/p" msgtxt2 >actual &&
	test_cmp expect actual &&
	sed -n -e "s/^Message-Id: *\(.*\)/\1/p" msgtxt2 >expect &&
	sed -n -e "s/^In-Reply-To: *\(.*\)/\1/p" msgtxt3 >actual &&
	test_cmp expect actual
'

test_expect_success PERL '--compose works' '
	clean_fake_sendmail &&
	git send-email \
	--compose --subject foo \
	--from="Example <nobody@example.com>" \
	--to=nobody@example.com \
	--confirm=never \
	--smtp-server="$(pwd)/fake.sendmail" \
	$patches \
	2>errors
'

test_expect_success PERL 'first message is compose text' '
	grep "^fake edit" msgtxt1
'

test_expect_success PERL 'second message is patch' '
	grep "Subject:.*Second" msgtxt2
'

test_expect_success PERL 'setup expect' "
cat >expected-suppress-sob <<\EOF
0001-Second.patch
(mbox) Adding cc: A <author@example.com> from line 'From: A <author@example.com>'
(mbox) Adding cc: One <one@example.com> from line 'Cc: One <one@example.com>, two@example.com'
(mbox) Adding cc: two@example.com from line 'Cc: One <one@example.com>, two@example.com'
Dry-OK. Log says:
Server: relay.example.com
MAIL FROM:<from@example.com>
RCPT TO:<to@example.com>
RCPT TO:<cc@example.com>
RCPT TO:<author@example.com>
RCPT TO:<one@example.com>
RCPT TO:<two@example.com>
From: Example <from@example.com>
To: to@example.com
Cc: cc@example.com,
	A <author@example.com>,
	One <one@example.com>,
	two@example.com
Subject: [PATCH 1/1] Second.
Date: DATE-STRING
Message-Id: MESSAGE-ID-STRING
X-Mailer: X-MAILER-STRING
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit

Result: OK
EOF
"

test_suppression () {
	git send-email \
		--dry-run \
		--suppress-cc=$1 ${2+"--suppress-cc=$2"} \
		--from="Example <from@example.com>" \
		--to=to@example.com \
		--smtp-server relay.example.com \
		$patches | replace_variable_fields \
		>actual-suppress-$1${2+"-$2"} &&
	test_cmp expected-suppress-$1${2+"-$2"} actual-suppress-$1${2+"-$2"}
}

test_expect_success PERL 'sendemail.cc set' '
	git config sendemail.cc cc@example.com &&
	test_suppression sob
'

test_expect_success PERL 'setup expect' "
cat >expected-suppress-sob <<\EOF
0001-Second.patch
(mbox) Adding cc: A <author@example.com> from line 'From: A <author@example.com>'
(mbox) Adding cc: One <one@example.com> from line 'Cc: One <one@example.com>, two@example.com'
(mbox) Adding cc: two@example.com from line 'Cc: One <one@example.com>, two@example.com'
Dry-OK. Log says:
Server: relay.example.com
MAIL FROM:<from@example.com>
RCPT TO:<to@example.com>
RCPT TO:<author@example.com>
RCPT TO:<one@example.com>
RCPT TO:<two@example.com>
From: Example <from@example.com>
To: to@example.com
Cc: A <author@example.com>,
	One <one@example.com>,
	two@example.com
Subject: [PATCH 1/1] Second.
Date: DATE-STRING
Message-Id: MESSAGE-ID-STRING
X-Mailer: X-MAILER-STRING
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit

Result: OK
EOF
"

test_expect_success PERL 'sendemail.cc unset' '
	git config --unset sendemail.cc &&
	test_suppression sob
'

test_expect_success PERL 'setup expect' "
cat >expected-suppress-cccmd <<\EOF
0001-Second.patch
(mbox) Adding cc: A <author@example.com> from line 'From: A <author@example.com>'
(mbox) Adding cc: One <one@example.com> from line 'Cc: One <one@example.com>, two@example.com'
(mbox) Adding cc: two@example.com from line 'Cc: One <one@example.com>, two@example.com'
(body) Adding cc: C O Mitter <committer@example.com> from line 'Signed-off-by: C O Mitter <committer@example.com>'
Dry-OK. Log says:
Server: relay.example.com
MAIL FROM:<from@example.com>
RCPT TO:<to@example.com>
RCPT TO:<author@example.com>
RCPT TO:<one@example.com>
RCPT TO:<two@example.com>
RCPT TO:<committer@example.com>
From: Example <from@example.com>
To: to@example.com
Cc: A <author@example.com>,
	One <one@example.com>,
	two@example.com,
	C O Mitter <committer@example.com>
Subject: [PATCH 1/1] Second.
Date: DATE-STRING
Message-Id: MESSAGE-ID-STRING
X-Mailer: X-MAILER-STRING
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit

Result: OK
EOF
"

test_expect_success PERL 'sendemail.cccmd' '
	write_script cccmd <<-\EOF &&
	echo cc-cmd@example.com
	EOF
	git config sendemail.cccmd ./cccmd &&
	test_suppression cccmd
'

test_expect_success PERL 'setup expect' '
cat >expected-suppress-all <<\EOF
0001-Second.patch
Dry-OK. Log says:
Server: relay.example.com
MAIL FROM:<from@example.com>
RCPT TO:<to@example.com>
From: Example <from@example.com>
To: to@example.com
Subject: [PATCH 1/1] Second.
Date: DATE-STRING
Message-Id: MESSAGE-ID-STRING
X-Mailer: X-MAILER-STRING
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit

Result: OK
EOF
'

test_expect_success PERL '--suppress-cc=all' '
	test_suppression all
'

test_expect_success PERL 'setup expect' "
cat >expected-suppress-body <<\EOF
0001-Second.patch
(mbox) Adding cc: A <author@example.com> from line 'From: A <author@example.com>'
(mbox) Adding cc: One <one@example.com> from line 'Cc: One <one@example.com>, two@example.com'
(mbox) Adding cc: two@example.com from line 'Cc: One <one@example.com>, two@example.com'
(cc-cmd) Adding cc: cc-cmd@example.com from: './cccmd'
Dry-OK. Log says:
Server: relay.example.com
MAIL FROM:<from@example.com>
RCPT TO:<to@example.com>
RCPT TO:<author@example.com>
RCPT TO:<one@example.com>
RCPT TO:<two@example.com>
RCPT TO:<cc-cmd@example.com>
From: Example <from@example.com>
To: to@example.com
Cc: A <author@example.com>,
	One <one@example.com>,
	two@example.com,
	cc-cmd@example.com
Subject: [PATCH 1/1] Second.
Date: DATE-STRING
Message-Id: MESSAGE-ID-STRING
X-Mailer: X-MAILER-STRING
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit

Result: OK
EOF
"

test_expect_success PERL '--suppress-cc=body' '
	test_suppression body
'

test_expect_success PERL 'setup expect' "
cat >expected-suppress-body-cccmd <<\EOF
0001-Second.patch
(mbox) Adding cc: A <author@example.com> from line 'From: A <author@example.com>'
(mbox) Adding cc: One <one@example.com> from line 'Cc: One <one@example.com>, two@example.com'
(mbox) Adding cc: two@example.com from line 'Cc: One <one@example.com>, two@example.com'
Dry-OK. Log says:
Server: relay.example.com
MAIL FROM:<from@example.com>
RCPT TO:<to@example.com>
RCPT TO:<author@example.com>
RCPT TO:<one@example.com>
RCPT TO:<two@example.com>
From: Example <from@example.com>
To: to@example.com
Cc: A <author@example.com>,
	One <one@example.com>,
	two@example.com
Subject: [PATCH 1/1] Second.
Date: DATE-STRING
Message-Id: MESSAGE-ID-STRING
X-Mailer: X-MAILER-STRING
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit

Result: OK
EOF
"

test_expect_success PERL '--suppress-cc=body --suppress-cc=cccmd' '
	test_suppression body cccmd
'

test_expect_success PERL 'setup expect' "
cat >expected-suppress-sob <<\EOF
0001-Second.patch
(mbox) Adding cc: A <author@example.com> from line 'From: A <author@example.com>'
(mbox) Adding cc: One <one@example.com> from line 'Cc: One <one@example.com>, two@example.com'
(mbox) Adding cc: two@example.com from line 'Cc: One <one@example.com>, two@example.com'
Dry-OK. Log says:
Server: relay.example.com
MAIL FROM:<from@example.com>
RCPT TO:<to@example.com>
RCPT TO:<author@example.com>
RCPT TO:<one@example.com>
RCPT TO:<two@example.com>
From: Example <from@example.com>
To: to@example.com
Cc: A <author@example.com>,
	One <one@example.com>,
	two@example.com
Subject: [PATCH 1/1] Second.
Date: DATE-STRING
Message-Id: MESSAGE-ID-STRING
X-Mailer: X-MAILER-STRING
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit

Result: OK
EOF
"

test_expect_success PERL '--suppress-cc=sob' '
	test_might_fail git config --unset sendemail.cccmd &&
	test_suppression sob
'

test_expect_success PERL 'setup expect' "
cat >expected-suppress-bodycc <<\EOF
0001-Second.patch
(mbox) Adding cc: A <author@example.com> from line 'From: A <author@example.com>'
(mbox) Adding cc: One <one@example.com> from line 'Cc: One <one@example.com>, two@example.com'
(mbox) Adding cc: two@example.com from line 'Cc: One <one@example.com>, two@example.com'
(body) Adding cc: C O Mitter <committer@example.com> from line 'Signed-off-by: C O Mitter <committer@example.com>'
Dry-OK. Log says:
Server: relay.example.com
MAIL FROM:<from@example.com>
RCPT TO:<to@example.com>
RCPT TO:<author@example.com>
RCPT TO:<one@example.com>
RCPT TO:<two@example.com>
RCPT TO:<committer@example.com>
From: Example <from@example.com>
To: to@example.com
Cc: A <author@example.com>,
	One <one@example.com>,
	two@example.com,
	C O Mitter <committer@example.com>
Subject: [PATCH 1/1] Second.
Date: DATE-STRING
Message-Id: MESSAGE-ID-STRING
X-Mailer: X-MAILER-STRING
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit

Result: OK
EOF
"

test_expect_success PERL '--suppress-cc=bodycc' '
	test_suppression bodycc
'

test_expect_success PERL 'setup expect' "
cat >expected-suppress-cc <<\EOF
0001-Second.patch
(mbox) Adding cc: A <author@example.com> from line 'From: A <author@example.com>'
(body) Adding cc: C O Mitter <committer@example.com> from line 'Signed-off-by: C O Mitter <committer@example.com>'
Dry-OK. Log says:
Server: relay.example.com
MAIL FROM:<from@example.com>
RCPT TO:<to@example.com>
RCPT TO:<author@example.com>
RCPT TO:<committer@example.com>
From: Example <from@example.com>
To: to@example.com
Cc: A <author@example.com>,
	C O Mitter <committer@example.com>
Subject: [PATCH 1/1] Second.
Date: DATE-STRING
Message-Id: MESSAGE-ID-STRING
X-Mailer: X-MAILER-STRING
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit

Result: OK
EOF
"

test_expect_success PERL '--suppress-cc=cc' '
	test_suppression cc
'

test_no_confirm () {
	echo n | \
		git send-email \
		--from="Example <from@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		$@ \
		$patches >stdout &&
		! grep "Send this email" stdout
}

test_expect_success PERL 'No confirm with --suppress-cc' '
	test_no_confirm --suppress-cc=sob
'


test_expect_success PERL 'No confirm with --confirm=never' '
	test_no_confirm --confirm=never
'

test_expect_success PERL 'No confirm with sendemail.confirm=never' '
	test_config sendemail.confirm never &&
	test_no_confirm --compose --subject=foo
'

test_confirm () {
	echo y | \
		git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		$@ $patches >stdout &&
	grep "Send this email" stdout
}

test_expect_success PERL '--confirm=always' '
	test_config sendemail.confirm never &&
	test_confirm --confirm=always --suppress-cc=all
'

test_expect_success PERL '--confirm=auto' '
	test_config sendemail.confirm never &&
	test_confirm --confirm=auto
'

test_expect_success PERL '--confirm=cc' '
	test_config sendemail.confirm never &&
	test_confirm --confirm=cc
'

test_expect_success PERL '--confirm=compose' '
	test_config sendemail.confirm never &&
	test_confirm --confirm=compose --compose
'

test_expect_success PERL 'confirm by default (due to cc)' '
	test_unconfig sendemail.confirm &&
	test_confirm
'

test_expect_success PERL 'confirm by default (due to --compose)' '
	test_unconfig sendemail.confirm &&
	test_confirm --suppress-cc=all --compose
'

test_expect_success PERL 'confirm detects EOF (inform assumes y)' '
	test_unconfig sendemail.confirm &&
	rm -fr outdir &&
	git format-patch -2 -o outdir &&
		git send-email \
			--from="Example <nobody@example.com>" \
			--to=nobody@example.com \
			--smtp-server="$(pwd)/fake.sendmail" \
			outdir/*.patch </dev/null
'

test_expect_success PERL 'confirm detects EOF (auto causes failure)' '
	test_config sendemail.confirm auto &&
	test_must_fail git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		$patches </dev/null
'

test_expect_success PERL 'confirm does not loop forever' '
	test_unconfig sendemail.confirm &&
	yes "bogus" | test_must_fail git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		$patches
'

test_done
