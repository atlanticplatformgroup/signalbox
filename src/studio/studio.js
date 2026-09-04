const source = document.querySelector('#source');
const highlight = document.querySelector('#highlight');
const toast = document.querySelector('#toast');
let currentSource = '';
let candidateId = null;
let preview = null;
let validatedSource = null;

const templates = {
  blank: `// Define governed resources, operations, constraints, and approval rules.
model CustomerGovernance version "0.1.0";
`,
  github: `model GitHubGovernance version "0.1.0";

entity Agent @stableId("ent_10000000000000000000000000000001") {
  id: UUID @id @stableId("fld_10000000000000000000000000000001");
  active: Boolean = true @stableId("fld_10000000000000000000000000000002");
}
entity Repository @stableId("ent_10000000000000000000000000000002") {
  id: UUID @id @stableId("fld_10000000000000000000000000000003");
  owner: String @stableId("fld_10000000000000000000000000000004");
  name: String @stableId("fld_10000000000000000000000000000005");
}
entity IssueRequest @stableId("ent_10000000000000000000000000000003") {
  id: UUID @id @generated(uuid) @stableId("fld_10000000000000000000000000000006");
  repository: Repository @stableId("fld_10000000000000000000000000000007");
  requestedBy: Agent @stableId("fld_10000000000000000000000000000008");
  title: String @stableId("fld_10000000000000000000000000000009");
}
policy IssueDelegation @stableId("pol_10000000000000000000000000000001")(actor: Agent) {
  allow active_agent @stableId("pbr_10000000000000000000000000000001"): actor.active;
}
action createIssue @stableId("act_10000000000000000000000000000001")(
  caller actor: Agent, repository: Repository, title: String
) -> IssueRequest {
  authorize IssueDelegation(actor);
  idempotency required;
  create IssueRequest { repository = repository; requestedBy = actor; title = title; }
}
`,
  api: `model GovernedAPI version "0.1.0";

entity Agent @stableId("ent_20000000000000000000000000000001") {
  id: UUID @id @stableId("fld_20000000000000000000000000000001");
  active: Boolean = true @stableId("fld_20000000000000000000000000000002");
}
entity ApiResource @stableId("ent_20000000000000000000000000000002") {
  id: UUID @id @stableId("fld_20000000000000000000000000000003");
  path: String @unique @stableId("fld_20000000000000000000000000000004");
  production: Boolean = false @stableId("fld_20000000000000000000000000000005");
}
entity ApiRequest @stableId("ent_20000000000000000000000000000003") {
  id: UUID @id @generated(uuid) @stableId("fld_20000000000000000000000000000006");
  resource: ApiResource @stableId("fld_20000000000000000000000000000007");
  requestedBy: Agent @stableId("fld_20000000000000000000000000000008");
}
policy ApiDelegation @stableId("pol_20000000000000000000000000000001")(actor: Agent, resource: ApiResource) {
  allow active_nonproduction_agent @stableId("pbr_20000000000000000000000000000001"): actor.active and not resource.production;
}
action callApi @stableId("act_20000000000000000000000000000001")(
  caller actor: Agent, resource: ApiResource
) -> ApiRequest {
  authorize ApiDelegation(actor, resource);
  idempotency required;
  create ApiRequest { resource = resource; requestedBy = actor; }
}
`,
  database: `model GovernedDatabase version "0.1.0";

entity Agent @stableId("ent_30000000000000000000000000000001") {
  id: UUID @id @stableId("fld_30000000000000000000000000000001");
  active: Boolean = true @stableId("fld_30000000000000000000000000000002");
}
entity DatabaseResource @stableId("ent_30000000000000000000000000000002") {
  id: UUID @id @stableId("fld_30000000000000000000000000000003");
  name: String @unique @stableId("fld_30000000000000000000000000000004");
  production: Boolean = false @stableId("fld_30000000000000000000000000000005");
}
entity MigrationRequest @stableId("ent_30000000000000000000000000000003") {
  id: UUID @id @generated(uuid) @stableId("fld_30000000000000000000000000000006");
  database: DatabaseResource @stableId("fld_30000000000000000000000000000007");
  requestedBy: Agent @stableId("fld_30000000000000000000000000000008");
  migrationHash: String @stableId("fld_30000000000000000000000000000009");
}
policy MigrationApprovalBoundary @stableId("pol_30000000000000000000000000000001")(actor: Agent, database: DatabaseResource) {
  allow active_staging_agent @stableId("pbr_30000000000000000000000000000001"): actor.active and not database.production;
}
action requestMigration @stableId("act_30000000000000000000000000000001")(
  caller actor: Agent, database: DatabaseResource, migrationHash: String
) -> MigrationRequest {
  authorize MigrationApprovalBoundary(actor, database);
  idempotency required;
  create MigrationRequest { database = database; requestedBy = actor; migrationHash = migrationHash; }
}
`
};

function token(){ return sessionStorage.getItem('signalbox.token') || ''; }
function headers(){ return {'content-type':'application/json', authorization:`Bearer ${token()}`}; }
function notify(message){ toast.textContent=message; toast.classList.add('show'); setTimeout(()=>toast.classList.remove('show'),2400); }
function escape(value){ return value.replace(/[&<>]/g, char=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[char])); }
function paint(){
  let html=escape(source.value);
  html=html.replace(/(\/\/.*)$/gm,'<span class="comment">$1</span>')
    .replace(/(&quot;[^&]*?&quot;)/g,'<span class="str">$1</span>')
    .replace(/\b(model|version|enum|entity|policy|allow|action|query|caller|authorize|require|idempotency|create|update|returns|from|as|where|limit|and|or|not|true|false|null)\b/g,'<span class="kw">$1</span>')
    .replace(/\b(UUID|String|Boolean|DateTime|Int|Decimal)\b/g,'<span class="type">$1</span>');
  highlight.innerHTML=html.split('\n').map((line,index)=>`<span class="code-line" data-line="${index+1}">${line || ' '}</span>`).join('');
  highlight.scrollTop=source.scrollTop; highlight.scrollLeft=source.scrollLeft;
  const dirty=source.value!==currentSource;
  document.querySelector('#save-state').textContent=dirty?'Unsaved draft':'Saved locally';
}
function cursor(){ const before=source.value.slice(0,source.selectionStart).split('\n'); document.querySelector('#cursor').textContent=`Ln ${before.length}, Col ${before.at(-1).length+1}`; }
function setActive(active){
  document.querySelector('#active-version').textContent=active?`${active.model.name} · ${active.model.version}`:'No active model';
  document.querySelector('#active-hash').textContent=active?.model.sourceHash || 'Activate a compiled candidate to publish it.';
  document.querySelector('#rollback').disabled=!active?.previousVersionId;
}
function renderDiagnostics(items=[]){
  const list=document.querySelector('#diagnostic-list'); document.querySelector('#diagnostic-count').textContent=items.length;
  list.innerHTML=items.length?items.map(item=>`<li><button data-line="${item.line}" data-column="${item.column}">${item.code} · line ${item.line}:${item.column}</button><br>${escape(item.message)}</li>`).join(''):'<li class="empty">No diagnostics.</li>';
  list.querySelectorAll('button').forEach(button=>button.addEventListener('click',()=>goTo(Number(button.dataset.line),Number(button.dataset.column))));
}
function renderPreview(value, artifacts=[]){
  preview=value; const groups=[['Agents',value.agents],['Connectors',value.connectors],['Resources',value.resources],['Capabilities',value.capabilities],['Delegations',value.delegations],['Approval boundaries',value.approvalBoundaries],['Generated MCP tools',value.mcpTools],['Generated artifacts',artifacts]];
  document.querySelector('#surface-count').textContent=groups.slice(0,-1).reduce((sum,[,items])=>sum+items.length,0);
  document.querySelector('#preview-groups').innerHTML=groups.map(([name,items])=>`<section class="preview-group"><h3>${name} · ${items.length}</h3><div class="chips">${items.length?items.map(item=>`<span class="chip">${escape(item)}</span>`).join(''):'<span class="empty">None</span>'}</div></section>`).join('');
}
function setDocumentState(label, kind=''){
  const state=document.querySelector('#document-state'); state.textContent=label; state.className=`state-badge ${kind}`.trim();
}
function setCandidateState(title, detail, ready=false){
  const state=document.querySelector('#candidate-state'); state.classList.toggle('ready',ready); state.querySelector('strong').textContent=title; state.querySelector('small').textContent=detail;
}
function resetValidation(){
  candidateId=null; validatedSource=null;
  document.querySelector('#compile').disabled=true; document.querySelector('#activate').disabled=true;
  document.querySelector('#validation-state').textContent='Validation not run'; document.querySelector('#validation-state').className='status-idle';
  document.querySelector('#diagnostic-count').textContent='—'; setDocumentState('Draft'); setCandidateState('Not compiled','Validate first, then compile an isolated candidate.');
}
function goTo(line,column){ const lines=source.value.split('\n'); let pos=0; for(let i=0;i<line-1;i++)pos+=lines[i].length+1; source.focus(); source.setSelectionRange(pos+column-1,pos+column-1); cursor(); }
async function api(path, body){
  if(!token()){ document.querySelector('#token-dialog').showModal(); throw new Error('Access token required'); }
  const response=await fetch(path,{method:'POST',headers:headers(),body:JSON.stringify(body)}); const data=await response.json();
  if(!response.ok) throw new Error(data.message||`Request failed (${response.status})`); return data;
}
async function validate(){
  candidateId=null; document.querySelector('#activate').disabled=true; document.querySelector('#validate').disabled=true; document.querySelector('#validation-state').textContent='Validating…';
  try{ const data=await api('/studio/api/validate',{source:source.value}); renderDiagnostics(data.diagnostics);
    if(!data.ok){ validatedSource=null; document.querySelector('#compile').disabled=true; document.querySelector('#validation-state').textContent=`${data.diagnostics.length} error`; document.querySelector('#validation-state').className='status-error'; setDocumentState('Needs attention'); switchTab('diagnostics'); return data; }
    validatedSource=source.value; renderPreview(data.preview,data.artifacts); document.querySelector('#compile').disabled=false; document.querySelector('#validation-state').textContent='Validated'; document.querySelector('#validation-state').className='status-ok'; setDocumentState('Validated','valid'); switchTab('structure'); return data;
  }catch(error){validatedSource=null;document.querySelector('#validation-state').textContent='Validation failed';notify(error.message);return null;}
  finally{document.querySelector('#validate').disabled=false;}
}
async function compileCandidate(){
  if(validatedSource!==source.value){notify('Validate the current draft before compiling.');return;}
  document.querySelector('#compile').disabled=true; document.querySelector('#validation-state').textContent='Compiling candidate…';
  try{const data=await api('/studio/api/compile',{source:source.value});renderDiagnostics(data.diagnostics);
    if(!data.ok){document.querySelector('#validation-state').textContent='Compile failed';switchTab('diagnostics');return;}
    candidateId=data.candidateId;renderPreview(data.preview,data.artifacts);document.querySelector('#activate').disabled=false;document.querySelector('#validation-state').textContent='Candidate ready';setDocumentState('Candidate','candidate');setCandidateState(`${data.model.name} · ${data.model.version}`,`${data.model.sourceHash.slice(0,28)}…`,true);notify('Candidate compiled and ready to activate');
  }catch(error){document.querySelector('#validation-state').textContent='Compile failed';notify(error.message);}
  finally{if(!candidateId)document.querySelector('#compile').disabled=false;}
}
function switchTab(id){document.querySelectorAll('.inspector-tabs button[data-tab]').forEach(button=>button.classList.toggle('active',button.dataset.tab===id));document.querySelectorAll('.tab-panel').forEach(panel=>panel.classList.toggle('active',panel.id===id));}

source.addEventListener('input',()=>{paint();cursor();resetValidation();localStorage.setItem('signalbox.model.draft',source.value);});
source.addEventListener('scroll',paint);source.addEventListener('click',cursor);source.addEventListener('keyup',cursor);
source.addEventListener('keydown',event=>{if(event.key==='Tab'){event.preventDefault();source.setRangeText('  ',source.selectionStart,source.selectionEnd,'end');source.dispatchEvent(new Event('input'));}});
document.querySelector('#validate').addEventListener('click',validate);
document.querySelector('#validate-empty').addEventListener('click',validate);
document.querySelector('#compile').addEventListener('click',compileCandidate);
document.querySelector('#format').addEventListener('click',()=>{source.value=source.value.split('\n').map(line=>line.replace(/\s+$/,'')).join('\n').trim()+'\n';source.dispatchEvent(new Event('input'));notify('Whitespace normalized');});
document.querySelector('#template').addEventListener('change',event=>{const selected=event.target.value;if(!selected)return;if(source.value!==currentSource&&!window.confirm('Replace the current unsaved draft?')){event.target.value='';return;}source.value=templates[selected];event.target.value='';source.dispatchEvent(new Event('input'));source.focus();});
document.querySelector('#activate').addEventListener('click',async()=>{if(!candidateId)return;try{const data=await api('/studio/api/activate',{candidateId});candidateId=null;validatedSource=source.value;document.querySelector('#activate').disabled=true;document.querySelector('#compile').disabled=true;currentSource=source.value;localStorage.removeItem('signalbox.model.draft');paint();setActive(data.active);setDocumentState('Active','valid');setCandidateState('Activated',`${data.active.model.name} · ${data.active.model.version}`);document.querySelector('#validation-state').textContent='Active';notify('Candidate activated');}catch(error){notify(error.message);}});
document.querySelector('#rollback').addEventListener('click',async()=>{try{const data=await api('/studio/api/rollback',{});setActive(data.active);notify('Prior version restored');}catch(error){notify(error.message);}});
document.querySelector('#configure-token').addEventListener('click',()=>document.querySelector('#token-dialog').showModal());
document.querySelector('#save-token').addEventListener('click',()=>{sessionStorage.setItem('signalbox.token',document.querySelector('#token').value.trim());notify('Access token stored for this session');});
document.querySelectorAll('.inspector-tabs button[data-tab]').forEach(button=>button.addEventListener('click',()=>switchTab(button.dataset.tab)));
document.querySelector('#toggle-inspector').addEventListener('click',event=>{const collapsed=document.querySelector('#workspace').classList.toggle('inspector-collapsed');event.currentTarget.textContent=collapsed?'‹':'×';event.currentTarget.setAttribute('aria-label',collapsed?'Expand inspector':'Collapse inspector');});
window.addEventListener('beforeunload',event=>{if(source.value!==currentSource){event.preventDefault();event.returnValue='';}});

try{
  const response=await fetch('/studio/api/bootstrap',{headers:{authorization:`Bearer ${token()}`}});
  if(response.status===401){document.querySelector('#token-dialog').showModal();throw new Error('Authenticate to load the governance model.');}
  const data=await response.json();if(!response.ok)throw new Error(data.message||'Bootstrap failed');
  const draft=localStorage.getItem('signalbox.model.draft');currentSource=data.source;source.value=draft||data.source;setActive(data.active);paint();cursor();resetValidation();
  if(!draft&&data.active){setDocumentState('Active','valid');document.querySelector('#validation-state').textContent='Active';}
}catch(error){currentSource=templates.blank;source.value=localStorage.getItem('signalbox.model.draft')||currentSource;setActive(null);paint();cursor();resetValidation();notify(error.message);}
