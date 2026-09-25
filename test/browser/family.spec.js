const {test, expect} = require('@playwright/test');
const fs = require('node:fs');
test('independent family modules, content refresh and preserved layout draft', async ({page, request}) => {
  test.setTimeout(120000);
  await page.goto('/login');
  await page.locator('[name=password]').fill(process.env.ADMIN_PASSWORD || 'development-password');
  await page.getByRole('button', {name:'Zaloguj',exact:true}).click();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  const today = new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Warsaw'}).format(new Date());
  const data = [
    ['today_tomorrow','Odbiór dzieci',null,'Anna','Świetlica'],
    ['dinner','Zupa pomidorowa','18:00','Tata','Z ryżem'],
    ['reminders','Książki do biblioteki',null,'Ola',''],
    ['countdowns','Wspólny spacer',null,'Wszyscy',''],
    ['family_note','Miłego dnia!',null,'Mama','Pamiętajcie o parasolach.']
  ];
  await page.locator('#tab-content').click();
  page.on('dialog', d => d.accept());
  for (const [kind,title,time,owner,body] of data) {
    await page.locator('#module-'+kind).click();
    await expect(page.locator('#module-'+kind)).toHaveAttribute('aria-pressed','true');
    // Fixture deployment only; remove previous runs.
    while (await page.locator('.family-row').count()) {
      const count = await page.locator('.family-row').count();
      await page.locator('[id^=delete-family-]').first().click();
      await expect(page.locator('.family-row')).toHaveCount(count-1);
    }
    await page.locator('[name="family[title]"]').fill(title);
    await page.locator('[name="family[date]"]').fill(today);
    if (time) await page.locator('[name="family[time]"]').fill(time);
    await page.locator('[name="family[owner]"]').fill(owner);
    await page.locator('[name="family[body]"]').fill(body);
    await page.locator('#family-save').click();
    await expect(page.locator('.family-row')).toContainText(title);
    await expect(page.locator('[name="family[title]"]')).toHaveValue('');
    if (time) await expect(page.locator('[name="family[time]"]')).toHaveValue('');
  }
  await page.locator('#module-today_tomorrow').click();
  await expect(page.locator('#module-today_tomorrow')).toHaveAttribute('aria-pressed','true');
  for (const title of ['Podlać kwiaty', 'Wynieść śmieci']) {
    await page.locator('[name="family[title]"]').fill(title);
    await page.locator('[name="family[date]"]').fill(today);
    await page.locator('#family-save').click();
    await expect(page.locator('[name="family[title]"]')).toHaveValue('');
  }
  await expect(page.locator('.family-row')).toHaveCount(3);
  await page.locator('[name="family[title]"]').fill('Czwarte zadanie');
  await page.locator('#family-save').click();
  await expect(page.locator('#family-form .error')).toContainText('3 zadania');
  await expect(page.locator('.family-row')).toHaveCount(3);
  await page.locator('[id^=complete-]').first().click();
  await expect(page.locator('[id^=restore-]')).toHaveCount(1);
  await page.locator('#module-reminders').click();
  await expect(page.locator('#module-reminders')).toHaveAttribute('aria-pressed','true');
  await page.locator('[id^=complete-]').click();
  await expect(page.locator('[id^=restore-]')).toBeVisible();
  await page.locator('[id^=restore-]').click();
  await expect(page.locator('[id^=complete-]')).toBeVisible();
  await page.locator('#module-dinner').click();
  await expect(page.locator('#module-dinner')).toHaveAttribute('aria-pressed','true');
  await page.screenshot({path:'artifacts/family-dashboard.png',fullPage:true});
  await page.locator('#tab-layout').click();
  while (await page.locator('.grid-block').count()) {
    const count = await page.locator('.grid-block').count();
    await page.locator('.grid-block').first().click();
    await page.locator('#remove-block').click();
    await expect(page.locator('.grid-block')).toHaveCount(count-1);
  }
  for (const [index, [kind]] of data.entries()) {
    await page.locator('#add-'+kind).click();
    await expect(page.locator('.grid-block')).toHaveCount(index+1);
  }
  await page.locator('#publish').click();
  await expect(page.locator('#notice')).toContainText('Opublikowano');
  await page.locator('#preview').click();
  await expect(page.locator('#preview-image')).toBeVisible({timeout:15000});
  const src = await page.locator('#preview-image').getAttribute('src');
  const png = Buffer.from(src.split(',')[1],'base64');
  expect(png.readUInt32BE(16)).toBe(800);
  expect(png.readUInt32BE(20)).toBe(480);
  expect(png[24]).toBe(1); expect(png[25]).toBe(0);
  fs.writeFileSync('artifacts/family-screen.png',png);
  await page.locator('#tab-settings').click();
  await page.locator('[name=mac]').fill('AA:BB:CC:DD:EE:FF');
  await page.locator('#pair-form button').click();
  await expect(page.locator('#notice')).toContainText('10 minut');
  const setup = await (await request.get('/api/setup',{headers:{id:'AA:BB:CC:DD:EE:FF'}})).json();
  const headers = {id:'AA:BB:CC:DD:EE:FF','access-token':setup.api_key};
  const display = async () => (await (await request.get('/api/display',{headers})).json()).filename;
  const before = await display();
  await page.locator('#tab-layout').click();
  await page.locator('.grid-block').first().click();
  await expect(page.locator('.grid-block').first()).toHaveClass(/selected/);
  await page.locator('[name="block[title]"]').fill('UNPUBLISHED');
  await page.locator('#apply-block').click();
  await expect(page.locator('.grid-block').first()).toContainText('UNPUBLISHED');
  await page.locator('#tab-content').click();
  await page.locator('#module-dinner').click();
  await expect(page.locator('#module-dinner')).toHaveAttribute('aria-pressed','true');
  await page.locator('[id^=edit-family-]').click();
  await expect(page.locator('#family-new')).toBeVisible();
  await page.locator('[name="family[title]"]').fill('Pierogi ze szpinakiem');
  await page.locator('#family-save').click();
  await expect(page.locator('.family-row')).toContainText('Pierogi ze szpinakiem');
  await expect.poll(display,{timeout:30000}).not.toBe(before);
  await page.locator('#tab-layout').click();
  await expect(page.locator('.grid-block').first()).toContainText('UNPUBLISHED');
  await page.reload();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('.grid-block').first()).not.toContainText('UNPUBLISHED');
  await page.locator('#tab-content').click();
  await page.locator('#module-dinner').click();
  await expect(page.locator('#module-dinner')).toHaveAttribute('aria-pressed','true');
  await expect(page.locator('.family-row')).toContainText('Pierogi ze szpinakiem');
});
