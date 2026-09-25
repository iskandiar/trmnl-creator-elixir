const {defineConfig} = require('@playwright/test');
module.exports = defineConfig({testDir: './test/browser', workers: 1, timeout: 60000, use: {baseURL: process.env.BASE_URL || 'http://127.0.0.1:4010', viewport: {width:1440,height:1100}, screenshot:'only-on-failure'}});
