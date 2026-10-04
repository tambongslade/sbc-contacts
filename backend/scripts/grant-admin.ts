/**
 * Give (or take back) back-office access. Roles live only in our database,
 * so this is how the first admins are made.
 *
 *   npx ts-node scripts/grant-admin.ts <email | phone | name | sbcUserId>
 *   npx ts-node scripts/grant-admin.ts <who> --revoke
 *
 * Refuses when the search matches several members, so nobody is promoted by
 * accident.
 */
import { PrismaClient, Role } from '@prisma/client';

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const revoke = args.includes('--revoke');
  const who = args
    .filter((a) => a !== '--revoke')
    .join(' ')
    .trim();
  if (!who) {
    console.error(
      'Usage: npx ts-node scripts/grant-admin.ts <email | phone | name | sbcUserId> [--revoke]',
    );
    process.exit(1);
  }

  const prisma = new PrismaClient();
  try {
    const users = await prisma.user.findMany({
      where: {
        OR: [
          { sbcUserId: who },
          { email: { equals: who, mode: 'insensitive' } },
          { phoneNumber: { contains: who.replace(/\D/g, '') || who } },
          { name: { contains: who, mode: 'insensitive' } },
        ],
      },
      select: { id: true, name: true, email: true, phoneNumber: true, role: true },
    });
    if (users.length === 0) {
      console.error(`No member matches "${who}". They must have signed in to the app once.`);
      process.exit(1);
    }
    if (users.length > 1) {
      console.error(`"${who}" matches ${users.length} members — be more precise:`);
      for (const u of users)
        console.error(
          `  ${u.name ?? '—'} · ${u.email ?? '—'} · ${u.phoneNumber ?? '—'} (${u.role})`,
        );
      process.exit(1);
    }
    const [user] = users;
    if (user.role === Role.SUPER_ADMIN && revoke) {
      console.error('Refusing to demote a SUPER_ADMIN from this script.');
      process.exit(1);
    }
    const role = revoke
      ? Role.USER
      : user.role === Role.SUPER_ADMIN
        ? Role.SUPER_ADMIN
        : Role.ADMIN;
    await prisma.user.update({ where: { id: user.id }, data: { role } });
    console.log(`${user.name ?? user.email ?? user.id}: ${user.role} → ${role}`);
  } finally {
    await prisma.$disconnect();
  }
}

void main();
