const {test, expect} = require('@playwright/test');
const fs = require('node:fs');

test('login recovery, responsive tabs, calendar appearances and stale preview', async ({page}) => {
  await page.goto('/login');
  await page.locator('[name=password]').fill('incorrect');
  await page.getByRole('button', {name:'Zaloguj', exact:true}).click();
  await expect(page.getByRole('alert')).toBeVisible();
  await page.locator('[name=password]').fill(process.env.ADMIN_PASSWORD || 'development-password');
  await page.getByRole('button', {name:'Zaloguj', exact:true}).click();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  // Only disposable validation data; layout changes remain unpublished.
  while (await page.locator('.grid-block').count()) {
    const count = await page.locator('.grid-block').count();
    await page.locator('.grid-block').first().click();
    await expect(page.locator('.grid-block').first()).toHaveClass(/selected/);
    await page.locator('#remove-block').click();
    await expect(page.locator('.grid-block')).toHaveCount(count - 1);
  }
  await page.locator('#add-month').click();
  await expect(page.locator('.grid-block')).toHaveCount(1);
  await page.locator('#block-appearance').selectOption('contrast');
  await page.locator('#block-density').selectOption('comfortable');
  await page.locator('#apply-block').click();
  await page.locator('#preview').click();
  await expect(page.locator('#preview-image')).toBeVisible({timeout:15000});
  await page.locator('[name="block[title]"]').fill('Nowy tytuł miesiąca');
  await page.locator('#apply-block').click();
  await expect(page.locator('#preview-stale')).toBeVisible();
  await page.locator('#save').click();
  await expect(page.locator('#notice')).toContainText('Zapisano');
  await page.reload();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.locator('.grid-block').focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('#block-appearance')).toHaveValue('contrast');
  await expect(page.locator('#block-density')).toHaveValue('comfortable');
  await page.locator('#tab-content').focus();
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('#tab-layout')).toHaveAttribute('aria-selected','true');
  await page.setViewportSize({width:390,height:844});
  for (const name of ['content','settings','layout']) {
    await page.locator('#tab-'+name).click();
    await expect(page.locator('#pane-'+name)).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    fs.mkdirSync('artifacts',{recursive:true});
    await page.screenshot({path:'artifacts/ux-mobile-'+name+'.png',fullPage:true});
  }
  await page.setViewportSize({width:1440,height:1000});
  await page.screenshot({path:'artifacts/ux-desktop.png',fullPage:true});
});
