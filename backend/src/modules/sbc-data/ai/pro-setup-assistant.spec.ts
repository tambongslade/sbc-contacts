import { ServiceMode } from '@prisma/client';
import { missingFields, sanitise } from './pro-setup-assistant';

/**
 * The assistant may say "c'est fini" whenever it likes; these checks are what
 * actually decide whether a pro can be found. A profile let through with a
 * placeholder city never matches anyone, and the pro pays for nothing.
 */
describe('Pro setup assistant checks', () => {
  const full = () =>
    sanitise({
      profile: {
        profession: 'Coiffeur',
        description: 'Je fais les locks à Yaoundé.',
        city: 'Yaoundé',
        zones: ['Bastos'],
        modes: [ServiceMode.HOME],
        availability: 'Lun–sam',
        priceMin: null,
        priceMax: null,
        shopUrl: 'https://sbcshop.com/aicha',
      },
      services: [
        {
          name: 'Pose de locks',
          category: 'Locks',
          profession: 'Coiffeur',
          synonyms: [],
          specialties: [],
        },
      ],
    });

  it('accepts a profile with everything matching needs', () => {
    expect(missingFields(full(), false)).toEqual([]);
  });

  it('treats "À compléter" placeholders as missing', () => {
    const d = full();
    const placeholder = sanitise({
      ...d,
      profile: { ...d.profile, city: 'À compléter', profession: 'à compléter' },
    });
    expect(missingFields(placeholder, false)).toEqual(
      expect.arrayContaining(['city', 'profession']),
    );
  });

  it('refuses a stand-in shop link', () => {
    const d = full();
    expect(
      missingFields(
        sanitise({ ...d, profile: { ...d.profile, shopUrl: 'https://example.com' } }),
        false,
      ),
    ).toContain('shopUrl');
    expect(
      missingFields(sanitise({ ...d, profile: { ...d.profile, shopUrl: 'ma boutique' } }), false),
    ).toContain('shopUrl');
  });

  it('needs a service unless the pro already has one', () => {
    const d = { ...full(), services: [] };
    expect(missingFields(d, false)).toEqual(['services']);
    expect(missingFields(d, true)).toEqual([]);
  });

  it('drops unknown modes, duplicate services and negative prices from what the model returns', () => {
    const d = sanitise({
      profile: {
        ...full().profile,
        modes: ['HOME', 'TELEPORT' as ServiceMode, 'HOME'],
        priceMin: -5,
      },
      services: [
        { name: 'Pose de locks', category: '', profession: '', synonyms: [], specialties: [] },
        { name: 'pose de locks', category: '', profession: '', synonyms: [], specialties: [] },
      ],
    });
    expect(d.profile.modes).toEqual([ServiceMode.HOME]);
    expect(d.profile.priceMin).toBeNull();
    expect(d.services).toHaveLength(1);
    expect(d.services[0].category).toBe('Pose de locks');
  });
});
