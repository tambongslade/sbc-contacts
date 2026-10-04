/**
 * Create (or update) a back-office admin that signs in with email + password.
 * Password auth is the exception — SBC SSO stays the default — so this is a
 * deliberate manual script, never an API.
 *
 *   ADMIN_EMAIL=you@example.com ADMIN_PASSWORD='secret' \
 *     npx ts-node scripts/create-password-admin.ts ["Display name"]
 *
 * or positionally:
 *   npx ts-node scripts/create-password-admin.ts <email> <password> ["Display name"]
 *
 * If a user with that email already exists (e.g. an SBC account), it just sets
 * the password + ADMIN role on it. Otherwise it makes a local, SSO-less account
 * with a synthetic sbcUserId.
 */
import { PrismaClient, Role } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const email = (process.env.ADMIN_EMAIL ?? args[0] ?? '').trim().toLowerCase();
  const password = process.env.ADMIN_PASSWORD ?? args[1] ?? '';
  const name =
    (process.env.ADMIN_NAME ?? (process.env.ADMIN_PASSWORD ? args.join(' ') : args.slice(2).join(' ')))
      .trim() || null;

  if (!email || !password) {
    console.error(
      'Usage: ADMIN_EMAIL=.. ADMIN_PASSWORD=.. npx ts-node scripts/create-password-admin.ts ["Name"]',
    );
    process.exit(1);
  }

  const prisma = new PrismaClient();
  try {
    const passwordHash = await bcrypt.hash(password, 12);
    const existing = await prisma.user.findFirst({
      where: { email: { equals: email, mode: 'insensitive' } },
    });
    if (existing) {
      const role = existing.role === Role.SUPER_ADMIN ? Role.SUPER_ADMIN : Role.ADMIN;
      await prisma.user.update({
        where: { id: existing.id },
        data: { passwordHash, role, isActivated: true, ...(name ? { name } : {}) },
      });
      console.log(`Updated ${email}: password set, role=${role}`);
    } else {
      const sbcUserId = `local-admin:${email}`;
      await prisma.user.create({
        data: {
          sbcUserId,
          email,
          name: name ?? 'Admin',
          role: Role.ADMIN,
          isActivated: true,
          passwordHash,
        },
      });
      console.log(`Created local admin ${email} (sbcUserId=${sbcUserId}), role=ADMIN`);
    }
  } finally {
    await prisma.$disconnect();
  }
}

void main();
