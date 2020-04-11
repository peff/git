#!/bin/sh

test_description='more send-email tests'
. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-send-email.sh

test_expect_success PERL 'utf8 Cc is rfc2047 encoded' '
	clean_fake_sendmail &&
	rm -fr outdir &&
	git format-patch -1 -o outdir --cc="àéìöú <utf8@example.com>" &&
	git send-email \
	--from="Example <nobody@example.com>" \
	--to=nobody@example.com \
	--smtp-server="$(pwd)/fake.sendmail" \
	outdir/*.patch &&
	grep "^	" msgtxt1 |
	grep "=?UTF-8?q?=C3=A0=C3=A9=C3=AC=C3=B6=C3=BA?= <utf8@example.com>"
'

test_expect_success PERL '--compose adds MIME for utf8 body' '
	clean_fake_sendmail &&
	write_script fake-editor-utf8 <<-\EOF &&
	echo "utf8 body: àéìöú" >>"$1"
	EOF
	GIT_EDITOR="\"$(pwd)/fake-editor-utf8\"" \
	git send-email \
		--compose --subject foo \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--confirm=never \
		$patches &&
	grep "^utf8 body" msgtxt1 &&
	grep "^Content-Type: text/plain; charset=UTF-8" msgtxt1
'

test_expect_success PERL '--compose respects user mime type' '
	clean_fake_sendmail &&
	write_script fake-editor-utf8-mime <<-\EOF &&
	cat >"$1" <<-\EOM
	MIME-Version: 1.0
	Content-Type: text/plain; charset=iso-8859-1
	Content-Transfer-Encoding: 8bit
	Subject: foo

	utf8 body: àéìöú
	EOM
	EOF
	GIT_EDITOR="\"$(pwd)/fake-editor-utf8-mime\"" \
	git send-email \
		--compose --subject foo \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--confirm=never \
		$patches &&
	grep "^utf8 body" msgtxt1 &&
	grep "^Content-Type: text/plain; charset=iso-8859-1" msgtxt1 &&
	! grep "^Content-Type: text/plain; charset=UTF-8" msgtxt1
'

test_expect_success PERL '--compose adds MIME for utf8 subject' '
	clean_fake_sendmail &&
	GIT_EDITOR="\"$(pwd)/fake-editor\"" \
	git send-email \
		--compose --subject utf8-sübjëct \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--confirm=never \
		$patches &&
	grep "^fake edit" msgtxt1 &&
	grep "^Subject: =?UTF-8?q?utf8-s=C3=BCbj=C3=ABct?=" msgtxt1
'

test_expect_success PERL 'utf8 author is correctly passed on' '
	clean_fake_sendmail &&
	test_commit weird_author &&
	test_when_finished "git reset --hard HEAD^" &&
	git commit --amend --author "Füñný Nâmé <odd_?=mail@example.com>" &&
	git format-patch --stdout -1 >funny_name.patch &&
	git send-email --from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		funny_name.patch &&
	grep "^From: Füñný Nâmé <odd_?=mail@example.com>" msgtxt1
'

test_expect_success PERL 'utf8 sender is not duplicated' '
	clean_fake_sendmail &&
	test_commit weird_sender &&
	test_when_finished "git reset --hard HEAD^" &&
	git commit --amend --author "Füñný Nâmé <odd_?=mail@example.com>" &&
	git format-patch --stdout -1 >funny_name.patch &&
	git send-email --from="Füñný Nâmé <odd_?=mail@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		funny_name.patch &&
	grep "^From: " msgtxt1 >msgfrom &&
	test_line_count = 1 msgfrom
'

test_expect_success PERL 'sendemail.composeencoding works' '
	clean_fake_sendmail &&
	git config sendemail.composeencoding iso-8859-1 &&
	write_script fake-editor-utf8 <<-\EOF &&
	echo "utf8 body: àéìöú" >>"$1"
	EOF
	GIT_EDITOR="\"$(pwd)/fake-editor-utf8\"" \
	git send-email \
		--compose --subject foo \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--confirm=never \
		$patches &&
	grep "^utf8 body" msgtxt1 &&
	grep "^Content-Type: text/plain; charset=iso-8859-1" msgtxt1
'

test_expect_success PERL '--compose-encoding works' '
	clean_fake_sendmail &&
	write_script fake-editor-utf8 <<-\EOF &&
	echo "utf8 body: àéìöú" >>"$1"
	EOF
	GIT_EDITOR="\"$(pwd)/fake-editor-utf8\"" \
	git send-email \
		--compose-encoding iso-8859-1 \
		--compose --subject foo \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--confirm=never \
		$patches &&
	grep "^utf8 body" msgtxt1 &&
	grep "^Content-Type: text/plain; charset=iso-8859-1" msgtxt1
'

test_expect_success PERL '--compose-encoding overrides sendemail.composeencoding' '
	clean_fake_sendmail &&
	git config sendemail.composeencoding iso-8859-1 &&
	write_script fake-editor-utf8 <<-\EOF &&
	echo "utf8 body: àéìöú" >>"$1"
	EOF
	GIT_EDITOR="\"$(pwd)/fake-editor-utf8\"" \
	git send-email \
		--compose-encoding iso-8859-2 \
		--compose --subject foo \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--confirm=never \
		$patches &&
	grep "^utf8 body" msgtxt1 &&
	grep "^Content-Type: text/plain; charset=iso-8859-2" msgtxt1
'

test_expect_success PERL '--compose-encoding adds correct MIME for subject' '
	clean_fake_sendmail &&
	GIT_EDITOR="\"$(pwd)/fake-editor\"" \
	git send-email \
		--compose-encoding iso-8859-2 \
		--compose --subject utf8-sübjëct \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--confirm=never \
		$patches &&
	grep "^fake edit" msgtxt1 &&
	grep "^Subject: =?iso-8859-2?q?utf8-s=C3=BCbj=C3=ABct?=" msgtxt1
'

test_expect_success PERL 'detects ambiguous reference/file conflict' '
	echo master >master &&
	git add master &&
	git commit -m"add master" &&
	test_must_fail git send-email --dry-run master 2>errors &&
	grep disambiguate errors
'

test_expect_success PERL 'feed two files' '
	rm -fr outdir &&
	git format-patch -2 -o outdir &&
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		outdir/000?-*.patch 2>errors >out &&
	grep "^Subject: " out >subjects &&
	test "z$(sed -n -e 1p subjects)" = "zSubject: [PATCH 1/2] Second." &&
	test "z$(sed -n -e 2p subjects)" = "zSubject: [PATCH 2/2] add master"
'

test_expect_success PERL 'in-reply-to but no threading' '
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--in-reply-to="<in-reply-id@example.com>" \
		--no-thread \
		$patches >out &&
	grep "In-Reply-To: <in-reply-id@example.com>" out
'

test_expect_success PERL 'no in-reply-to and no threading' '
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--no-thread \
		$patches >stdout &&
	! grep "In-Reply-To: " stdout
'

test_expect_success PERL 'threading but no chain-reply-to' '
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--thread \
		--no-chain-reply-to \
		$patches $patches >stdout &&
	grep "In-Reply-To: " stdout
'

test_expect_success PERL 'override in-reply-to if no threading' '
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--no-thread \
		--in-reply-to="override" \
		$threaded_patches >stdout &&
	grep "In-Reply-To: <override>" stdout
'

test_expect_success PERL 'sendemail.to works' '
	git config --replace-all sendemail.to "Somebody <somebody@ex.com>" &&
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		$patches >stdout &&
	grep "To: Somebody <somebody@ex.com>" stdout
'

test_expect_success PERL 'setup sendemail.identity' '
	git config --replace-all sendemail.to "default@example.com" &&
	git config --replace-all sendemail.isp.to "isp@example.com" &&
	git config --replace-all sendemail.cloud.to "cloud@example.com"
'

test_expect_success PERL 'sendemail.identity: reads the correct identity config' '
	git -c sendemail.identity=cloud send-email \
		--dry-run \
		--from="nobody@example.com" \
		$patches >stdout &&
	grep "To: cloud@example.com" stdout
'

test_expect_success PERL 'sendemail.identity: identity overrides sendemail.identity' '
	git -c sendemail.identity=cloud send-email \
		--identity=isp \
		--dry-run \
		--from="nobody@example.com" \
		$patches >stdout &&
	grep "To: isp@example.com" stdout
'

test_expect_success PERL 'sendemail.identity: --no-identity clears previous identity' '
	git -c sendemail.identity=cloud send-email \
		--no-identity \
		--dry-run \
		--from="nobody@example.com" \
		$patches >stdout &&
	grep "To: default@example.com" stdout
'

test_expect_success PERL 'sendemail.identity: bool identity variable existence overrides' '
	git -c sendemail.identity=cloud \
		-c sendemail.xmailer=true \
		-c sendemail.cloud.xmailer=false \
		send-email \
		--dry-run \
		--from="nobody@example.com" \
		$patches >stdout &&
	grep "To: cloud@example.com" stdout &&
	! grep "X-Mailer" stdout
'

test_expect_success PERL 'sendemail.identity: bool variable fallback' '
	git -c sendemail.identity=cloud \
		-c sendemail.xmailer=false \
		send-email \
		--dry-run \
		--from="nobody@example.com" \
		$patches >stdout &&
	grep "To: cloud@example.com" stdout &&
	! grep "X-Mailer" stdout
'

test_expect_success PERL '--no-to overrides sendemail.to' '
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--no-to \
		--to=nobody@example.com \
		$patches >stdout &&
	grep "To: nobody@example.com" stdout &&
	! grep "To: Somebody <somebody@ex.com>" stdout
'

test_expect_success PERL 'sendemail.cc works' '
	git config --replace-all sendemail.cc "Somebody <somebody@ex.com>" &&
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		$patches >stdout &&
	grep "Cc: Somebody <somebody@ex.com>" stdout
'

test_expect_success PERL '--no-cc overrides sendemail.cc' '
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--no-cc \
		--cc=bodies@example.com \
		--to=nobody@example.com \
		$patches >stdout &&
	grep "Cc: bodies@example.com" stdout &&
	! grep "Cc: Somebody <somebody@ex.com>" stdout
'

test_expect_success PERL 'sendemail.bcc works' '
	git config --replace-all sendemail.bcc "Other <other@ex.com>" &&
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server relay.example.com \
		$patches >stdout &&
	grep "RCPT TO:<other@ex.com>" stdout
'

test_expect_success PERL '--no-bcc overrides sendemail.bcc' '
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--no-bcc \
		--bcc=bodies@example.com \
		--to=nobody@example.com \
		--smtp-server relay.example.com \
		$patches >stdout &&
	grep "RCPT TO:<bodies@example.com>" stdout &&
	! grep "RCPT TO:<other@ex.com>" stdout
'

test_expect_success PERL 'patches To headers are used by default' '
	patch=$(git format-patch -1 --to="bodies@example.com") &&
	test_when_finished "rm $patch" &&
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--smtp-server relay.example.com \
		$patch >stdout &&
	grep "RCPT TO:<bodies@example.com>" stdout
'

test_expect_success PERL 'patches To headers are appended to' '
	patch=$(git format-patch -1 --to="bodies@example.com") &&
	test_when_finished "rm $patch" &&
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server relay.example.com \
		$patch >stdout &&
	grep "RCPT TO:<bodies@example.com>" stdout &&
	grep "RCPT TO:<nobody@example.com>" stdout
'

test_expect_success PERL 'To headers from files reset each patch' '
	patch1=$(git format-patch -1 --to="bodies@example.com") &&
	patch2=$(git format-patch -1 --to="other@example.com" HEAD~) &&
	test_when_finished "rm $patch1 && rm $patch2" &&
	git send-email \
		--dry-run \
		--from="Example <nobody@example.com>" \
		--to="nobody@example.com" \
		--smtp-server relay.example.com \
		$patch1 $patch2 >stdout &&
	test $(grep -c "RCPT TO:<bodies@example.com>" stdout) = 1 &&
	test $(grep -c "RCPT TO:<nobody@example.com>" stdout) = 2 &&
	test $(grep -c "RCPT TO:<other@example.com>" stdout) = 1
'

test_expect_success PERL 'setup expect' '
cat >email-using-8bit <<\EOF
From fe6ecc66ece37198fe5db91fa2fc41d9f4fe5cc4 Mon Sep 17 00:00:00 2001
Message-Id: <bogus-message-id@example.com>
From: author@example.com
Date: Sat, 12 Jun 2010 15:53:58 +0200
Subject: subject goes here

Dieser deutsche Text enthält einen Umlaut!
EOF
'

test_expect_success PERL 'setup expect' '
	echo "Subject: subject goes here" >expected
'

test_expect_success PERL 'ASCII subject is not RFC2047 quoted' '
	clean_fake_sendmail &&
	echo bogus |
	git send-email --from=author@example.com --to=nobody@example.com \
			--smtp-server="$(pwd)/fake.sendmail" \
			--8bit-encoding=UTF-8 \
			email-using-8bit >stdout &&
	grep "Subject" msgtxt1 >actual &&
	test_cmp expected actual
'

test_expect_success PERL 'setup expect' '
	cat >content-type-decl <<-\EOF
	MIME-Version: 1.0
	Content-Type: text/plain; charset=UTF-8
	Content-Transfer-Encoding: 8bit
	EOF
'

test_expect_success PERL 'asks about and fixes 8bit encodings' '
	clean_fake_sendmail &&
	echo |
	git send-email --from=author@example.com --to=nobody@example.com \
			--smtp-server="$(pwd)/fake.sendmail" \
			email-using-8bit >stdout &&
	grep "do not declare a Content-Transfer-Encoding" stdout &&
	grep email-using-8bit stdout &&
	grep "Which 8bit encoding" stdout &&
	egrep "Content|MIME" msgtxt1 >actual &&
	test_cmp content-type-decl actual
'

test_expect_success PERL 'sendemail.8bitEncoding works' '
	clean_fake_sendmail &&
	git config sendemail.assume8bitEncoding UTF-8 &&
	echo bogus |
	git send-email --from=author@example.com --to=nobody@example.com \
			--smtp-server="$(pwd)/fake.sendmail" \
			email-using-8bit >stdout &&
	egrep "Content|MIME" msgtxt1 >actual &&
	test_cmp content-type-decl actual
'

test_expect_success PERL '--8bit-encoding overrides sendemail.8bitEncoding' '
	clean_fake_sendmail &&
	git config sendemail.assume8bitEncoding "bogus too" &&
	echo bogus |
	git send-email --from=author@example.com --to=nobody@example.com \
			--smtp-server="$(pwd)/fake.sendmail" \
			--8bit-encoding=UTF-8 \
			email-using-8bit >stdout &&
	egrep "Content|MIME" msgtxt1 >actual &&
	test_cmp content-type-decl actual
'

test_expect_success PERL 'setup expect' '
	cat >email-using-8bit <<-\EOF
	From fe6ecc66ece37198fe5db91fa2fc41d9f4fe5cc4 Mon Sep 17 00:00:00 2001
	Message-Id: <bogus-message-id@example.com>
	From: author@example.com
	Date: Sat, 12 Jun 2010 15:53:58 +0200
	Subject: Dieser Betreff enthält auch einen Umlaut!

	Nothing to see here.
	EOF
'

test_expect_success PERL 'setup expect' '
	cat >expected <<-\EOF
	Subject: =?UTF-8?q?Dieser=20Betreff=20enth=C3=A4lt=20auch=20einen=20Umlaut!?=
	EOF
'

test_expect_success PERL '--8bit-encoding also treats subject' '
	clean_fake_sendmail &&
	echo bogus |
	git send-email --from=author@example.com --to=nobody@example.com \
			--smtp-server="$(pwd)/fake.sendmail" \
			--8bit-encoding=UTF-8 \
			email-using-8bit >stdout &&
	grep "Subject" msgtxt1 >actual &&
	test_cmp expected actual
'

test_expect_success PERL 'setup expect' '
	cat >email-using-8bit <<-\EOF
	From fe6ecc66ece37198fe5db91fa2fc41d9f4fe5cc4 Mon Sep 17 00:00:00 2001
	Message-Id: <bogus-message-id@example.com>
	From: A U Thor <author@example.com>
	Date: Sat, 12 Jun 2010 15:53:58 +0200
	Content-Type: text/plain; charset=UTF-8
	Subject: Nothing to see here.

	Dieser Betreff enthält auch einen Umlaut!
	EOF
'

test_expect_success PERL '--transfer-encoding overrides sendemail.transferEncoding' '
	clean_fake_sendmail &&
	test_must_fail git -c sendemail.transferEncoding=8bit \
		send-email \
		--transfer-encoding=7bit \
		--smtp-server="$(pwd)/fake.sendmail" \
		email-using-8bit \
		2>errors >out &&
	grep "cannot send message as 7bit" errors &&
	test -z "$(ls msgtxt*)"
'

test_expect_success PERL 'sendemail.transferEncoding via config' '
	clean_fake_sendmail &&
	test_must_fail git -c sendemail.transferEncoding=7bit \
		send-email \
		--smtp-server="$(pwd)/fake.sendmail" \
		email-using-8bit \
		2>errors >out &&
	grep "cannot send message as 7bit" errors &&
	test -z "$(ls msgtxt*)"
'

test_expect_success PERL 'sendemail.transferEncoding via cli' '
	clean_fake_sendmail &&
	test_must_fail git send-email \
		--transfer-encoding=7bit \
		--smtp-server="$(pwd)/fake.sendmail" \
		email-using-8bit \
		2>errors >out &&
	grep "cannot send message as 7bit" errors &&
	test -z "$(ls msgtxt*)"
'

test_expect_success PERL 'setup expect' '
	cat >expected <<-\EOF
	Dieser Betreff enth=C3=A4lt auch einen Umlaut!
	EOF
'

test_expect_success PERL '8-bit and sendemail.transferencoding=quoted-printable' '
	clean_fake_sendmail &&
	git send-email \
		--transfer-encoding=quoted-printable \
		--smtp-server="$(pwd)/fake.sendmail" \
		email-using-8bit \
		2>errors >out &&
	sed "1,/^$/d" msgtxt1 >actual &&
	test_cmp expected actual
'

test_expect_success PERL 'setup expect' '
	cat >expected <<-\EOF
	RGllc2VyIEJldHJlZmYgZW50aMOkbHQgYXVjaCBlaW5lbiBVbWxhdXQhCg==
	EOF
'

test_expect_success PERL '8-bit and sendemail.transferencoding=base64' '
	clean_fake_sendmail &&
	git send-email \
		--transfer-encoding=base64 \
		--smtp-server="$(pwd)/fake.sendmail" \
		email-using-8bit \
		2>errors >out &&
	sed "1,/^$/d" msgtxt1 >actual &&
	test_cmp expected actual
'

test_expect_success PERL 'setup expect' '
	cat >email-using-qp <<-\EOF
	From fe6ecc66ece37198fe5db91fa2fc41d9f4fe5cc4 Mon Sep 17 00:00:00 2001
	Message-Id: <bogus-message-id@example.com>
	From: A U Thor <author@example.com>
	Date: Sat, 12 Jun 2010 15:53:58 +0200
	MIME-Version: 1.0
	Content-Transfer-Encoding: quoted-printable
	Content-Type: text/plain; charset=UTF-8
	Subject: Nothing to see here.

	Dieser Betreff enth=C3=A4lt auch einen Umlaut!
	EOF
'

test_expect_success PERL 'convert from quoted-printable to base64' '
	clean_fake_sendmail &&
	git send-email \
		--transfer-encoding=base64 \
		--smtp-server="$(pwd)/fake.sendmail" \
		email-using-qp \
		2>errors >out &&
	sed "1,/^$/d" msgtxt1 >actual &&
	test_cmp expected actual
'

test_expect_success PERL 'setup expect' "
tr -d '\\015' | tr '%' '\\015' >email-using-crlf <<EOF
From fe6ecc66ece37198fe5db91fa2fc41d9f4fe5cc4 Mon Sep 17 00:00:00 2001
Message-Id: <bogus-message-id@example.com>
From: A U Thor <author@example.com>
Date: Sat, 12 Jun 2010 15:53:58 +0200
Content-Type: text/plain; charset=UTF-8
Subject: Nothing to see here.

Look, I have a CRLF and an = sign!%
EOF
"

test_expect_success PERL 'setup expect' '
	cat >expected <<-\EOF
	Look, I have a CRLF and an =3D sign!=0D
	EOF
'

test_expect_success PERL 'CRLF and sendemail.transferencoding=quoted-printable' '
	clean_fake_sendmail &&
	git send-email \
		--transfer-encoding=quoted-printable \
		--smtp-server="$(pwd)/fake.sendmail" \
		email-using-crlf \
		2>errors >out &&
	sed "1,/^$/d" msgtxt1 >actual &&
	test_cmp expected actual
'

test_expect_success PERL 'setup expect' '
	cat >expected <<-\EOF
	TG9vaywgSSBoYXZlIGEgQ1JMRiBhbmQgYW4gPSBzaWduIQ0K
	EOF
'

test_expect_success PERL 'CRLF and sendemail.transferencoding=base64' '
	clean_fake_sendmail &&
	git send-email \
		--transfer-encoding=base64 \
		--smtp-server="$(pwd)/fake.sendmail" \
		email-using-crlf \
		2>errors >out &&
	sed "1,/^$/d" msgtxt1 >actual &&
	test_cmp expected actual
'


# Note that the patches in this test are deliberately out of order; we
# want to make sure it works even if the cover-letter is not in the
# first mail.
test_expect_success PERL 'refusing to send cover letter template' '
	clean_fake_sendmail &&
	rm -fr outdir &&
	git format-patch --cover-letter -2 -o outdir &&
	test_must_fail git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		outdir/0002-*.patch \
		outdir/0000-*.patch \
		outdir/0001-*.patch \
		2>errors >out &&
	grep "SUBJECT HERE" errors &&
	test -z "$(ls msgtxt*)"
'

test_expect_success PERL '--force sends cover letter template anyway' '
	clean_fake_sendmail &&
	rm -fr outdir &&
	git format-patch --cover-letter -2 -o outdir &&
	git send-email \
		--force \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		outdir/0002-*.patch \
		outdir/0000-*.patch \
		outdir/0001-*.patch \
		2>errors >out &&
	! grep "SUBJECT HERE" errors &&
	test -n "$(ls msgtxt*)"
'

test_cover_addresses () {
	header="$1"
	shift
	clean_fake_sendmail &&
	rm -fr outdir &&
	git format-patch --cover-letter -2 -o outdir &&
	cover=$(echo outdir/0000-*.patch) &&
	mv $cover cover-to-edit.patch &&
	perl -pe "s/^From:/$header: extra\@address.com\nFrom:/" cover-to-edit.patch >"$cover" &&
	git send-email \
		--force \
		--from="Example <nobody@example.com>" \
		--no-to --no-cc \
		"$@" \
		--smtp-server="$(pwd)/fake.sendmail" \
		outdir/0000-*.patch \
		outdir/0001-*.patch \
		outdir/0002-*.patch \
		2>errors >out &&
	grep "^$header: extra@address.com" msgtxt1 >to1 &&
	grep "^$header: extra@address.com" msgtxt2 >to2 &&
	grep "^$header: extra@address.com" msgtxt3 >to3 &&
	test_line_count = 1 to1 &&
	test_line_count = 1 to2 &&
	test_line_count = 1 to3
}

test_expect_success PERL 'to-cover adds To to all mail' '
	test_cover_addresses "To" --to-cover
'

test_expect_success PERL 'cc-cover adds Cc to all mail' '
	test_cover_addresses "Cc" --cc-cover
'

test_expect_success PERL 'tocover adds To to all mail' '
	test_config sendemail.tocover true &&
	test_cover_addresses "To"
'

test_expect_success PERL 'cccover adds Cc to all mail' '
	test_config sendemail.cccover true &&
	test_cover_addresses "Cc"
'

test_expect_success PERL 'escaped quotes in sendemail.aliasfiletype=mutt' '
	clean_fake_sendmail &&
	echo "alias sbd \\\"Dot U. Sir\\\" <somebody@example.org>" >.mutt &&
	git config --replace-all sendemail.aliasesfile "$(pwd)/.mutt" &&
	git config sendemail.aliasfiletype mutt &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=sbd \
		--smtp-server="$(pwd)/fake.sendmail" \
		outdir/0001-*.patch \
		2>errors >out &&
	grep "^!somebody@example\.org!$" commandline1 &&
	grep -F "To: \"Dot U. Sir\" <somebody@example.org>" out
'

test_expect_success PERL 'sendemail.aliasfiletype=mailrc' '
	clean_fake_sendmail &&
	echo "alias sbd  somebody@example.org" >.mailrc &&
	git config --replace-all sendemail.aliasesfile "$(pwd)/.mailrc" &&
	git config sendemail.aliasfiletype mailrc &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=sbd \
		--smtp-server="$(pwd)/fake.sendmail" \
		outdir/0001-*.patch \
		2>errors >out &&
	grep "^!somebody@example\.org!$" commandline1
'

test_expect_success PERL 'sendemail.aliasfile=~/.mailrc' '
	clean_fake_sendmail &&
	echo "alias sbd  someone@example.org" >"$HOME/.mailrc" &&
	git config --replace-all sendemail.aliasesfile "~/.mailrc" &&
	git config sendemail.aliasfiletype mailrc &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=sbd \
		--smtp-server="$(pwd)/fake.sendmail" \
		outdir/0001-*.patch \
		2>errors >out &&
	grep "^!someone@example\.org!$" commandline1
'

test_dump_aliases () {
	msg="$1" && shift &&
	filetype="$1" && shift &&
	printf '%s\n' "$@" >expect &&
	cat >.tmp-email-aliases &&

	test_expect_success PERL "$msg" '
		clean_fake_sendmail && rm -fr outdir &&
		git config --replace-all sendemail.aliasesfile \
			"$(pwd)/.tmp-email-aliases" &&
		git config sendemail.aliasfiletype "$filetype" &&
		git send-email --dump-aliases 2>errors >actual &&
		test_cmp expect actual
	'
}

test_dump_aliases '--dump-aliases sendmail format' \
	'sendmail' \
	'abgroup' \
	'alice' \
	'bcgrp' \
	'bob' \
	'chloe' <<-\EOF
	alice: Alice W Land <awol@example.com>
	bob: Robert Bobbyton <bob@example.com>
	chloe: chloe@example.com
	abgroup: alice, bob
	bcgrp: bob, chloe, Other <o@example.com>
	EOF

test_dump_aliases '--dump-aliases mutt format' \
	'mutt' \
	'alice' \
	'bob' \
	'chloe' \
	'donald' <<-\EOF
	alias alice Alice W Land <awol@example.com>
	alias donald Donald C Carlton <donc@example.com>
	alias bob Robert Bobbyton <bob@example.com>
	alias chloe chloe@example.com
	EOF

test_dump_aliases '--dump-aliases mailrc format' \
	'mailrc' \
	'alice' \
	'bob' \
	'chloe' \
	'eve' <<-\EOF
	alias alice   Alice W Land <awol@example.com>
	alias eve     Eve <eve@example.com>
	alias bob     Robert Bobbyton <bob@example.com>
	alias chloe   chloe@example.com
	EOF

test_dump_aliases '--dump-aliases pine format' \
	'pine' \
	'alice' \
	'bob' \
	'chloe' \
	'eve' <<-\EOF
	alice	Alice W Land	<awol@example.com>
	eve	Eve	<eve@example.com>
	bob	Robert	Bobbyton <bob@example.com>
	chloe		chloe@example.com
	EOF

test_dump_aliases '--dump-aliases gnus format' \
	'gnus' \
	'alice' \
	'bob' \
	'chloe' \
	'eve' <<-\EOF
	(define-mail-alias "alice" "awol@example.com")
	(define-mail-alias "eve" "eve@example.com")
	(define-mail-alias "bob" "bob@example.com")
	(define-mail-alias "chloe" "chloe@example.com")
	EOF

test_expect_success '--dump-aliases must be used alone' '
	test_must_fail git send-email --dump-aliases --to=janice@example.com -1 refs/heads/accounting
'

test_expect_success PERL 'aliases and sendemail.identity' '
	test_must_fail git \
		-c sendemail.identity=cloud \
		-c sendemail.aliasesfile=default-aliases \
		-c sendemail.cloud.aliasesfile=cloud-aliases \
		send-email -1 2>stderr &&
	test_i18ngrep "cloud-aliases" stderr
'

test_sendmail_aliases () {
	msg="$1" && shift &&
	expect="$@" &&
	cat >.tmp-email-aliases &&

	test_expect_success PERL "$msg" '
		clean_fake_sendmail && rm -fr outdir &&
		git format-patch -1 -o outdir &&
		git config --replace-all sendemail.aliasesfile \
			"$(pwd)/.tmp-email-aliases" &&
		git config sendemail.aliasfiletype sendmail &&
		git send-email \
			--from="Example <nobody@example.com>" \
			--to=alice --to=bcgrp \
			--smtp-server="$(pwd)/fake.sendmail" \
			outdir/0001-*.patch \
			2>errors >out &&
		for i in $expect
		do
			grep "^!$i!$" commandline1 || return 1
		done
	'
}

test_sendmail_aliases 'sendemail.aliasfiletype=sendmail' \
	'awol@example\.com' \
	'bob@example\.com' \
	'chloe@example\.com' \
	'o@example\.com' <<-\EOF
	alice: Alice W Land <awol@example.com>
	bob: Robert Bobbyton <bob@example.com>
	# this is a comment
	   # this is also a comment
	chloe: chloe@example.com
	abgroup: alice, bob
	bcgrp: bob, chloe, Other <o@example.com>
	EOF

test_sendmail_aliases 'sendmail aliases line folding' \
	alice1 \
	bob1 bob2 \
	chuck1 chuck2 \
	darla1 darla2 darla3 \
	elton1 elton2 elton3 \
	fred1 fred2 \
	greg1 <<-\EOF
	alice: alice1
	bob: bob1,\
	bob2
	chuck: chuck1,
	    chuck2
	darla: darla1,\
	darla2,
	    darla3
	elton: elton1,
	    elton2,\
	elton3
	fred: fred1,\
	    fred2
	greg: greg1
	bcgrp: bob, chuck, darla, elton, fred, greg
	EOF

test_sendmail_aliases 'sendmail aliases tolerate bogus line folding' \
	alice1 bob1 <<-\EOF
	    alice: alice1
	bcgrp: bob1\
	EOF

test_sendmail_aliases 'sendmail aliases empty' alice bcgrp <<-\EOF
	EOF

test_expect_success PERL 'alias support in To header' '
	clean_fake_sendmail &&
	echo "alias sbd  someone@example.org" >.mailrc &&
	test_config sendemail.aliasesfile ".mailrc" &&
	test_config sendemail.aliasfiletype mailrc &&
	git format-patch --stdout -1 --to=sbd >aliased.patch &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--smtp-server="$(pwd)/fake.sendmail" \
		aliased.patch \
		2>errors >out &&
	grep "^!someone@example\.org!$" commandline1
'

test_expect_success PERL 'alias support in Cc header' '
	clean_fake_sendmail &&
	echo "alias sbd  someone@example.org" >.mailrc &&
	test_config sendemail.aliasesfile ".mailrc" &&
	test_config sendemail.aliasfiletype mailrc &&
	git format-patch --stdout -1 --cc=sbd >aliased.patch &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--smtp-server="$(pwd)/fake.sendmail" \
		aliased.patch \
		2>errors >out &&
	grep "^!someone@example\.org!$" commandline1
'

test_expect_success PERL 'tocmd works with aliases' '
	clean_fake_sendmail &&
	echo "alias sbd  someone@example.org" >.mailrc &&
	test_config sendemail.aliasesfile ".mailrc" &&
	test_config sendemail.aliasfiletype mailrc &&
	git format-patch --stdout -1 >tocmd.patch &&
	echo tocmd--sbd >>tocmd.patch &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to-cmd=./tocmd-sed \
		--smtp-server="$(pwd)/fake.sendmail" \
		tocmd.patch \
		2>errors >out &&
	grep "^!someone@example\.org!$" commandline1
'

test_expect_success PERL 'cccmd works with aliases' '
	clean_fake_sendmail &&
	echo "alias sbd  someone@example.org" >.mailrc &&
	test_config sendemail.aliasesfile ".mailrc" &&
	test_config sendemail.aliasfiletype mailrc &&
	git format-patch --stdout -1 >cccmd.patch &&
	echo cccmd--sbd >>cccmd.patch &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--cc-cmd=./cccmd-sed \
		--smtp-server="$(pwd)/fake.sendmail" \
		cccmd.patch \
		2>errors >out &&
	grep "^!someone@example\.org!$" commandline1
'

do_xmailer_test () {
	expected=$1 params=$2 &&
	git format-patch -1 &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=someone@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		--confirm=never \
		$params \
		0001-*.patch \
		2>errors >out &&
	{ grep '^X-Mailer:' out || :; } >mailer &&
	test_line_count = $expected mailer
}

test_expect_success PERL '--[no-]xmailer without any configuration' '
	do_xmailer_test 1 "--xmailer" &&
	do_xmailer_test 0 "--no-xmailer"
'

test_expect_success PERL '--[no-]xmailer with sendemail.xmailer=true' '
	test_config sendemail.xmailer true &&
	do_xmailer_test 1 "" &&
	do_xmailer_test 0 "--no-xmailer" &&
	do_xmailer_test 1 "--xmailer"
'

test_expect_success PERL '--[no-]xmailer with sendemail.xmailer=false' '
	test_config sendemail.xmailer false &&
	do_xmailer_test 0 "" &&
	do_xmailer_test 0 "--no-xmailer" &&
	do_xmailer_test 1 "--xmailer"
'

test_expect_success PERL 'setup expected-list' '
	git send-email \
	--dry-run \
	--from="Example <from@example.com>" \
	--to="To 1 <to1@example.com>" \
	--to="to2@example.com" \
	--to="to3@example.com" \
	--cc="Cc 1 <cc1@example.com>" \
	--cc="Cc2 <cc2@example.com>" \
	--bcc="bcc1@example.com" \
	--bcc="bcc2@example.com" \
	0001-add-master.patch | replace_variable_fields \
	>expected-list
'

test_expect_success PERL 'use email list in --cc --to and --bcc' '
	git send-email \
	--dry-run \
	--from="Example <from@example.com>" \
	--to="To 1 <to1@example.com>, to2@example.com" \
	--to="to3@example.com" \
	--cc="Cc 1 <cc1@example.com>, Cc2 <cc2@example.com>" \
	--bcc="bcc1@example.com, bcc2@example.com" \
	0001-add-master.patch | replace_variable_fields \
	>actual-list &&
	test_cmp expected-list actual-list
'

test_expect_success PERL 'aliases work with email list' '
	echo "alias to2 to2@example.com" >.mutt &&
	echo "alias cc1 Cc 1 <cc1@example.com>" >>.mutt &&
	test_config sendemail.aliasesfile ".mutt" &&
	test_config sendemail.aliasfiletype mutt &&
	git send-email \
	--dry-run \
	--from="Example <from@example.com>" \
	--to="To 1 <to1@example.com>, to2, to3@example.com" \
	--cc="cc1, Cc2 <cc2@example.com>" \
	--bcc="bcc1@example.com, bcc2@example.com" \
	0001-add-master.patch | replace_variable_fields \
	>actual-list &&
	test_cmp expected-list actual-list
'

test_expect_success PERL 'leading and trailing whitespaces are removed' '
	echo "alias to2 to2@example.com" >.mutt &&
	echo "alias cc1 Cc 1 <cc1@example.com>" >>.mutt &&
	test_config sendemail.aliasesfile ".mutt" &&
	test_config sendemail.aliasfiletype mutt &&
	TO1=$(echo "QTo 1 <to1@example.com>" | q_to_tab) &&
	TO2=$(echo "QZto2" | qz_to_tab_space) &&
	CC1=$(echo "cc1" | append_cr) &&
	BCC1=$(echo " bcc1@example.com Q" | q_to_nul) &&
	git send-email \
	--dry-run \
	--from="	Example <from@example.com>" \
	--to="$TO1" \
	--to="$TO2" \
	--to="  to3@example.com   " \
	--cc="$CC1" \
	--cc="Cc2 <cc2@example.com>" \
	--bcc="$BCC1" \
	--bcc="bcc2@example.com" \
	0001-add-master.patch | replace_variable_fields \
	>actual-list &&
	test_cmp expected-list actual-list
'

test_expect_success PERL 'invoke hook' '
	mkdir -p .git/hooks &&

	write_script .git/hooks/sendemail-validate <<-\EOF &&
	# test that we have the correct environment variable, pwd, and
	# argument
	case "$GIT_DIR" in
	*.git)
		true
		;;
	*)
		false
		;;
	esac &&
	test -f 0001-add-master.patch &&
	grep "add master" "$1"
	EOF

	mkdir subdir &&
	(
		# Test that it works even if we are not at the root of the
		# working tree
		cd subdir &&
		git send-email \
			--from="Example <nobody@example.com>" \
			--to=nobody@example.com \
			--smtp-server="$(pwd)/../fake.sendmail" \
			../0001-add-master.patch &&

		# Verify error message when a patch is rejected by the hook
		sed -e "s/add master/x/" ../0001-add-master.patch >../another.patch &&
		test_must_fail git send-email \
			--from="Example <nobody@example.com>" \
			--to=nobody@example.com \
			--smtp-server="$(pwd)/../fake.sendmail" \
			../another.patch 2>err &&
		test_i18ngrep "rejected by sendemail-validate hook" err
	)
'

test_expect_success PERL 'test that send-email works outside a repo' '
	nongit git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		"$(pwd)/0001-add-master.patch"
'

test_expect_success PERL 'test that sendmail config is rejected' '
	test_config sendmail.program sendmail &&
	test_must_fail git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		HEAD^ 2>err &&
	test_i18ngrep "found configuration options for '"'"sendmail"'"'" err
'

test_expect_success PERL 'test that sendmail config rejection is specific' '
	test_config resendmail.program sendmail &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		HEAD^
'

test_expect_success PERL 'test forbidSendmailVariables behavior override' '
	test_config sendmail.program sendmail &&
	test_config sendemail.forbidSendmailVariables false &&
	git send-email \
		--from="Example <nobody@example.com>" \
		--to=nobody@example.com \
		--smtp-server="$(pwd)/fake.sendmail" \
		HEAD^
'

test_done
