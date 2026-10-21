/**
 * Set up the SBC account App Review signs in with, so the reviewer goes from
 * "J'ai un compte SBC Network" straight to the app and never meets SBC's
 * sign-in page (or the code SBC may send there).
 *
 * Before running it, sign in to the app ONCE with that SBC account through
 * "Se connecter avec SBC": that stores its SBC session, which the server then
 * keeps alive by itself. Then:
 *
 *   npx ts-node scripts/set-review-login.ts <sbc-email> <whatsapp-number> <password>
 *
 * e.g. ... review@example.com +237690000001 'SbcReview2026'
 *
 * It sets the password and prints the two lines to add to backend/.env
 * (then `pm2 restart sbc-contacts-api --update-env`).
 */
import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { toInternationalPhone } from '../src/common/utils/phone';

async function main(): Promise<void> {
  const [rawEmail, rawPhone, password] = process.argv.slice(2);
  const email = (rawEmail ?? '').trim().toLowerCase();
  const phone = rawPhone ? toInternationalPhone(rawPhone) : null;

  if (!email || !password) {
    console.error(
      'Usage: npx ts-node scripts/set-review-login.ts <sbc-email> <whatsapp-number> <password>',
    );
    process.exit(1);
  }
  if (!phone || !rawPhone.trim().startsWith('+')) {
    console.error('Give the WhatsApp number with its country code, e.g. +237690000001');
    process.exit(1);
  }
  if (password.length < 8) {
    console.error('The password needs at least 8 characters (the app asks for that).');
    process.exit(1);
  }

  const prisma = new PrismaClient();
  try {
    const user = await prisma.user.findFirst({
      where: { email: { equals: email, mode: 'insensitive' }, origin: 'SBC', deletedAt: null },
      include: { sbcToken: true },
    });
    if (!user) {
      console.error(
        `No SBC account ${email} here yet. Sign in to the app once with it through ` +
          '"Se connecter avec SBC", then run this again.',
      );
      process.exit(1);
    }
    // A number an SBC Network account already uses would sign in here instead.
    const clash = await prisma.user.findFirst({
      where: { origin: 'NETWORK', phoneNumber: phone, deletedAt: null },
    });
    if (clash) {
      console.error(`+${phone} already belongs to an SBC Network account: pick another number.`);
      process.exit(1);
    }

    await prisma.user.update({
      where: { id: user.id },
      data: { passwordHash: await bcrypt.hash(password, 12) },
    });

    console.log(`Password set on ${email} (${user.name ?? 'no name'}).`);
    if (!user.sbcToken) {
      console.warn('! No SBC session stored: sign in once through "Se connecter avec SBC".');
    } else if (user.sbcToken.refreshExpiresAt < new Date()) {
      console.warn('! Its SBC session has expired: sign in again through "Se connecter avec SBC".');
    } else {
      console.log(`SBC session good until ${user.sbcToken.refreshExpiresAt.toISOString()}.`);
    }
    if (user.subscriptionTypes.length === 0) {
      console.warn('! No active SBC subscription: the reviewer would not see the directory.');
    }
    console.log('\nAdd to backend/.env, then pm2 restart sbc-contacts-api --update-env:\n');
    console.log(`APP_REVIEW_SBC_USER_ID=${user.sbcUserId}`);
    console.log(`APP_REVIEW_PHONE=+${phone}`);
  } finally {
    await prisma.$disconnect();
  }
}

void main();
