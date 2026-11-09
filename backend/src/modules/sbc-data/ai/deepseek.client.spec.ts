import { ConfigService } from '@nestjs/config';
import { AiUnavailableError } from './ai-unavailable.error';
import { DeepseekClient } from './deepseek.client';

/**
 * A cut or empty DeepSeek answer is asked once more; anything else (an HTTP
 * error, a second bad answer) is "AI unavailable" for the caller to handle.
 */
describe('DeepseekClient', () => {
  const config = { get: (k: string) => (k === 'deepseek.apiKey' ? 'test-key' : undefined) };
  const answer = (content: string, finish = 'stop') =>
    ({
      ok: true,
      json: () => Promise.resolve({ choices: [{ finish_reason: finish, message: { content } }] }),
    }) as Response;

  let fetchMock: jest.Mock;
  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  const client = () => new DeepseekClient(config as unknown as ConfigService);

  it('asks again once when the JSON comes back cut', async () => {
    fetchMock
      .mockResolvedValueOnce(answer('{"reply": "Où trav', 'length'))
      .mockResolvedValueOnce(answer('{"reply":"Où travailles-tu ?"}'));
    await expect(
      client().generateJsonChat('sys', [{ role: 'user', text: 'hi' }], {}),
    ).resolves.toEqual({
      reply: 'Où travailles-tu ?',
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).max_tokens).toBe(8192);
  });

  it('gives up after a second bad answer', async () => {
    fetchMock.mockResolvedValue(answer(''));
    await expect(
      client().generateJsonChat('sys', [{ role: 'user', text: 'hi' }], {}),
    ).rejects.toBeInstanceOf(AiUnavailableError);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does not retry an HTTP error', async () => {
    fetchMock.mockResolvedValue({
      ok: false,
      status: 402,
      text: () => Promise.resolve('Insufficient Balance'),
    });
    await expect(
      client().generateJsonChat('sys', [{ role: 'user', text: 'hi' }], {}),
    ).rejects.toBeInstanceOf(AiUnavailableError);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
