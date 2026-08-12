import { createApp } from 'vue';
import App from './app.vue';
import './styles.css';
import { auth } from './core/auth';

/**
 * App bootstrap. Auth is verified once up-front so the shell can decide
 * between the login gate and the dashboard. Panels are mounted lazily by the
 * registry, so this entry stays tiny regardless of how many panels exist.
 */
async function bootstrap(): Promise<void> {
  if (auth.state.token) {
    void auth.verify();
  }
  createApp(App).mount('#app');
}

void bootstrap();
