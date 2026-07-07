import { Container, getContainer } from '@cloudflare/containers';
import { env } from 'cloudflare:workers';
import { Hono } from 'hono';

export class PnprContainer extends Container<Env> {
  defaultPort = 7677;

  sleepAfter = '10m';

  // pnpr reads its YAML config after these values are injected.
  envVars = {
    PNPR_PUBLIC_URL: env.PNPR_PUBLIC_URL,
    PNPR_SECRET: env.PNPR_SECRET,
    PNPR_R2_ACCOUNT_ID: env.PNPR_R2_ACCOUNT_ID,
    PNPR_R2_BUCKET: env.PNPR_R2_BUCKET,
    PNPR_R2_ACCESS_KEY_ID: env.PNPR_R2_ACCESS_KEY_ID,
    PNPR_R2_SECRET_ACCESS_KEY: env.PNPR_R2_SECRET_ACCESS_KEY
  };

  override onStart() {
    console.log('pnpr container started');
  }

  override onStop({ exitCode, reason }: { exitCode?: number; reason?: string }) {
    console.log('pnpr container stopped', { exitCode, reason });
  }

  override onError(error: unknown) {
    console.error('pnpr container error', error);
    throw error;
  }
}

const app = new Hono<{
  Bindings: Env;
}>();

app.get('/', (c) => {
  return c.redirect('https://github.com/arthurfiorette/pnprcf');
});

app.all('/*', async (c) => {
  const container = getContainer(c.env.PNPR_CONTAINER, 'registry');
  return await container.fetch(c.req.raw);
});

export default app;
