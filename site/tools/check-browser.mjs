// Run against a local static server. PLAYWRIGHT_MODULE may point to an installed
// Playwright index.mjs; no browser dependency is added to the product.
import {pathToFileURL} from 'node:url';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const {chromium} = await import(process.env.PLAYWRIGHT_MODULE
  ? pathToFileURL(process.env.PLAYWRIGHT_MODULE).href : 'playwright');
const root = path.resolve(import.meta.dirname, '..');
const out = path.join(root, 'editorial/evidence');
await fs.mkdir(out, {recursive:true});
const base = process.env.SITE_URL || 'http://127.0.0.1:7826';
const xml = await fs.readFile(path.join(root, 'public/sitemap.xml'), 'utf8');
const routes = [...xml.matchAll(/<loc>https:\/\/kandong\.twtools\.cc([^<]*)<\/loc>/g)].map(m=>m[1]);
const browser = await chromium.launch({headless:true});
const results = {base, checkedAt: new Date().toISOString(), pages:[], links:[], numbers:[]};
const resources = new Set(['/llms.txt','/robots.txt','/sitemap.xml']);
const failures = [];
for (const route of routes) {
  const page = await browser.newPage({viewport:{width:390,height:844},isMobile:true,deviceScaleFactor:1});
  const errors = [];
  page.on('pageerror', e=>errors.push(e.message));
  // Analytics is not part of this layout/content check; don't send test visits.
  await page.route('**/googletagmanager.com/**', r=>r.fulfill({contentType:'text/javascript',body:''}));
  const response = await page.goto(base+route,{waitUntil:'networkidle',timeout:60000});
  assert.equal(response.status(),200,route);
  await page.locator('details').evaluateAll(nodes=>nodes.forEach(n=>n.open=true));
  const info = await page.evaluate(()=>{
    const blocks = [...document.querySelectorAll('script[type="application/ld+json"]')].flatMap(n=>{
      const parsed=JSON.parse(n.textContent); return parsed['@graph']||[parsed];
    });
    const text=n=>n.textContent.replace(/\s+/g,' ').trim();
    const faq = [...document.querySelectorAll('details')].map(n=>({q:text(n.querySelector('summary')),a:text(n).slice(text(n.querySelector('summary')).length).trim()}));
    for (const n of document.querySelectorAll('.faq-item')) faq.push({q:text(n.querySelector('h2')),a:text(n.querySelector('.faq-answer'))});
    const refs=[...document.querySelectorAll('a[href],img[src],link[rel="stylesheet"],link[rel="canonical"],meta[property="og:image"]')].map(n=>n.getAttribute('href')||n.getAttribute('src')||n.content);
    const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
    const numbers=[];
    while(walker.nextNode()) {
      const n=walker.currentNode, value=n.textContent.replace(/\s+/g,' ').trim();
      if(/\d/.test(value)&&!n.parentElement.closest('script,style')) numbers.push({tag:n.parentElement.tagName,text:value,
        tokens:value.match(/\d+(?:[.／–x-]\d+)*(?:GB|MB|B|x|%|秒|句)?/g)});
    }
    const h1=document.querySelector('h1');
    return {title:document.title,h1:text(h1),h1count:document.querySelectorAll('h1').length,
      nextAfterH1:h1.nextElementSibling?.className,quickAnswer:document.querySelector('.quick-answer')?.textContent,
      canonical:document.querySelector('link[rel="canonical"]')?.href,blocks,faq,refs,numbers,
      images:[...document.images].map(n=>({src:n.getAttribute('src'),loaded:n.complete&&n.naturalWidth>0}))};
  });
  assert.equal(info.h1count,1,route+' h1');
  assert.equal(info.canonical,'https://kandong.twtools.cc'+route);
  const schemaFAQ=info.blocks.filter(n=>n['@type']==='FAQPage');
  assert.equal(schemaFAQ.length,info.faq.length?1:0,route+' FAQ exists iff rendered');
  if(info.faq.length) assert.deepEqual(schemaFAQ[0].mainEntity.map(n=>({q:n.name,a:n.acceptedAnswer.text})),info.faq,route+' FAQ exact text');
  if(route.startsWith('/articles/')&&route!='/articles/' || route==='/faq/') {
    assert.equal(info.blocks.filter(n=>n['@type']==='Article').length,1,route+' Article');
    assert.equal(info.nextAfterH1,'quick-answer');
    const article=info.blocks.find(n=>n['@type']==='Article');
    assert.equal(article.headline,info.h1);
    assert.equal(article.mainEntityOfPage,info.canonical);
    assert.ok(article.datePublished.endsWith('+08:00'));
    assert.ok(info.refs.includes('/guide/'));
    assert.ok(info.refs.includes('https://github.com/dvdmaru/kandong/releases/latest'));
  }
  results.numbers.push({route,passages:info.numbers});
  for(const ref of info.refs) if(!ref.startsWith('data:')) resources.add(new URL(ref, 'https://kandong.twtools.cc'+route).href);
  const sizes=[];
  for(const width of [320,390,768,1440]) {
    await page.setViewportSize({width,height:900});
    const overflow=await page.evaluate(()=>{
      // Detect elements outside the viewport even if an ancestor hides overflow.
      const width=document.documentElement.clientWidth;
      return {viewport:width,scrollWidth:document.documentElement.scrollWidth,elements:[...document.body.querySelectorAll('*')]
        .filter(n=>!['SCRIPT','STYLE','LINK','META'].includes(n.tagName))
        .map(n=>({n,r:n.getBoundingClientRect()})).filter(({n,r})=>r.width>0 && (r.right>width+1||r.left < -1) && getComputedStyle(n).position!=='absolute')
        .map(({n,r})=>({tag:n.tagName,text:n.textContent.slice(0,65),left:r.left,right:r.right}))};
    });
    sizes.push({width,...overflow});
    if(overflow.scrollWidth>width || overflow.elements.length) failures.push({route,width,overflow});
    if([390,1440].includes(width)) await page.screenshot({path:path.join(out,`${route.replaceAll('/','_')||'home'}-${width}.png`),fullPage:true});
  }
  if(info.images.some(n=>!n.loaded)) failures.push({route,images:info.images});
  if(errors.length) failures.push({route,errors});
  results.pages.push({route,...info,numbers:undefined,refs:undefined,sizes,errors});
  await page.close();
}
for(const ref of resources) {
  const url=new URL(ref,base);
  if(url.origin!=='https://kandong.twtools.cc' && url.origin!==new URL(base).origin) {
    results.links.push({url:ref,external:true}); continue;
  }
  const response=await fetch(base+url.pathname+url.search);
  const checked={url:ref,status:response.status};
  if(!response.ok) failures.push(checked);
  if(url.hash) {
    const doc=await response.text();
    checked.anchor=url.hash;
    checked.anchorFound=url.hash==='#' || doc.includes(`id="${decodeURIComponent(url.hash.slice(1))}"`);
    if(!checked.anchorFound) failures.push(checked);
  }
  results.links.push(checked);
}
results.failures=failures;
await fs.writeFile(path.join(out,'browser.json'),JSON.stringify(results,null,2)+'\n');
await browser.close();
console.log(JSON.stringify({pages:results.pages.length,links:results.links.length,failures}));
assert.equal(failures.length,0,'Browser/content/link checks failed');
