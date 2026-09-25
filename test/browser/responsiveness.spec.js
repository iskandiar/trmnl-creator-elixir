const {test, expect} = require('@playwright/test');
async function login(page) {
  await page.goto('/login');
  await page.locator('[name=password]').fill(process.env.ADMIN_PASSWORD || 'development-password');
  await page.getByRole('button', {name:'Zaloguj', exact:true}).click();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
}
test('block follows the pointer before release without a server round trip', async ({page}) => {
  await login(page);
  if (await page.locator('.grid-block').count() === 0) {
    await page.locator('#add-text').click();
    await expect(page.locator('.grid-block')).toHaveCount(1);
  }
  const block = page.locator('.grid-block').first();
  const before = await block.boundingBox();
  await page.mouse.move(before.x+30,before.y+30);
  await page.mouse.down();
  try {
    await page.mouse.move(before.x+70,before.y+70);
    await expect.poll(async () => Math.round((await block.boundingBox()).x-before.x), {timeout:500}).toBe(40);
      await page.mouse.move(before.x+930,before.y+70);
  } finally { await page.mouse.up(); }
  await expect.poll(async () => Math.round((await block.boundingBox()).x-before.x)).toBe(0);
  // No Save/Publish: the persisted user layout is left untouched.
});
test('Google connection never redirects with an empty client ID', async ({page}) => {
  await login(page);
  const response = await page.request.get('/oauth/start',{maxRedirects:0});
  const location = response.headers().location;
  const url = new URL(location, page.url());
  if (url.hostname === 'accounts.google.com') {
    console.log(JSON.stringify({clientConfigured:!!url.searchParams.get('client_id'), callbackOrigin:new URL(url.searchParams.get('redirect_uri')).origin}));
    expect(Boolean(url.searchParams.get('client_id')?.trim())).toBe(true);
  } else {
    expect(url.origin).toBe(new URL(page.url()).origin);
    await page.goto(location);
    await page.locator('#tab-settings').click();
    await expect(page.getByText(/Skonfiguruj Google OAuth/).first()).toBeVisible();
  }
});

test('resize is visible before release and Escape restores original dimensions', async ({page}) => {
  await login(page);
  if (await page.locator('.grid-block').count() === 0) {
    await page.locator('#add-text').click();
    await expect(page.locator('.grid-block')).toHaveCount(1);
  }
  const block = page.locator('.grid-block').first();
  const before = await block.boundingBox();
  const handle = await block.locator('.resize').boundingBox();
  await page.mouse.move(handle.x+5,handle.y+5); await page.mouse.down();
  await page.mouse.move(handle.x+45,handle.y+45);
  await expect.poll(async () => Math.round((await block.boundingBox()).width-before.width), {timeout:500}).toBe(40);
  await page.keyboard.press('Escape'); await page.mouse.up();
  await expect.poll(async () => Math.round((await block.boundingBox()).width-before.width)).toBe(0);
});
