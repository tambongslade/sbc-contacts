module.exports = {
  apps: [
    {
      name: 'sbc-contacts-api',
      script: 'dist/main.js',
      cwd: '/var/www/sbc-contacts/backend',
      instances: 1,
      exec_mode: 'fork',
      max_memory_restart: '400M',
      env: {
        NODE_ENV: 'production',
      },
    },
  ],
};
