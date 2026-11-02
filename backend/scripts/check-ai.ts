/**
 * Is the AI working? Calls Gemini the way SBC Data does and says what fails.
 * The app degrades silently to keyword matching when Gemini is down, so this
 * is how to tell "no AI" from "no matching pro".
 *
 *   npx ts-node scripts/check-ai.ts
 *
 * Reads GEMINI_API_KEY / GEMINI_MODEL / GEMINI_EMBEDDING_MODEL from .env.
 * Never prints the key.
 */
try {
  process.loadEnvFile('.env');
} catch {
  /* no .env: rely on the environment */
}

const API = 'https://generativelanguage.googleapis.com/v1beta';

async function call(path: string, init?: RequestInit): Promise<{ status: number; body: any }> {
  const started = Date.now();
  const res = await fetch(`${API}/${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': process.env.GEMINI_API_KEY ?? '',
    },
    signal: AbortSignal.timeout(60_000),
  });
  const text = await res.text();
  let body: any = text;
  try {
    body = JSON.parse(text);
  } catch {
    /* keep the text */
  }
  console.log(`  → HTTP ${res.status} in ${Date.now() - started} ms`);
  return { status: res.status, body };
}

async function main(): Promise<void> {
  const key = process.env.GEMINI_API_KEY ?? '';
  const model = process.env.GEMINI_MODEL || 'gemini-flash-latest';
  const embeddingModel = process.env.GEMINI_EMBEDDING_MODEL || 'gemini-embedding-001';
  if (!key) {
    console.error('✗ GEMINI_API_KEY is not set: the AI is off.');
    process.exit(1);
  }
  console.log(`Model: ${model} · embeddings: ${embeddingModel}\n`);

  console.log('1. Structured generation (what analyses a request)');
  const gen = await call(`models/${model}:generateContent`, {
    method: 'POST',
    body: JSON.stringify({
      contents: [
        { role: 'user', parts: [{ text: 'Je cherche un plombier à Yaoundé pour une fuite.' }] },
      ],
      systemInstruction: { parts: [{ text: 'Extrais le métier et la ville.' }] },
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema: {
          type: 'OBJECT',
          properties: { metier: { type: 'STRING' }, ville: { type: 'STRING' } },
          required: ['metier', 'ville'],
        },
        temperature: 0.1,
      },
    }),
  });
  const parts: Array<{ text?: string; thought?: boolean }> =
    gen.body?.candidates?.[0]?.content?.parts ?? [];
  const answer = parts
    .filter((p) => !p.thought && p.text)
    .map((p) => p.text)
    .join('');
  if (gen.status !== 200) console.log(`  ✗ ${JSON.stringify(gen.body).slice(0, 500)}`);
  else if (!answer) console.log(`  ✗ no answer text: ${JSON.stringify(gen.body).slice(0, 500)}`);
  else console.log(`  ✓ ${answer}`);

  console.log('\n2. Embeddings (what ranks pros by meaning)');
  const emb = await call(`models/${embeddingModel}:batchEmbedContents`, {
    method: 'POST',
    body: JSON.stringify({
      requests: [
        {
          model: `models/${embeddingModel}`,
          content: { parts: [{ text: 'plomberie' }] },
          taskType: 'RETRIEVAL_QUERY',
          outputDimensionality: 768,
        },
      ],
    }),
  });
  const dims = emb.body?.embeddings?.[0]?.values?.length;
  if (emb.status === 200 && dims) console.log(`  ✓ ${dims} dimensions`);
  else console.log(`  ✗ ${JSON.stringify(emb.body).slice(0, 500)}`);

  console.log('\n3. Flash models this key can use');
  const list = await call('models?pageSize=200');
  const names: string[] = (list.body?.models ?? [])
    .filter((m: any) => m.supportedGenerationMethods?.includes('generateContent'))
    .map((m: any) => String(m.name).replace('models/', ''))
    .filter((n: string) => n.includes('flash'));
  console.log(
    names.length ? `  ${names.join('\n  ')}` : `  ✗ ${JSON.stringify(list.body).slice(0, 300)}`,
  );
}

main().catch((err) => {
  console.error(`✗ ${(err as Error).message}`);
  process.exit(1);
});
