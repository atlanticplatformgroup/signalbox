const source = document.querySelector('#source');
const highlight = document.querySelector('#highlight');
const toast = document.querySelector('#toast');
const draftKey = 'signalbox.policy.draft';
let currentSource = '';
let baselineSource = null;
let candidateId = null;
let validatedSource = null;
let activePolicy = null;
let canAdministerGovernance = false;
let sessionGeneration = 0;
let activityRequest = 0;
let bootstrapRequest = 0;
let operationNames = {};

function token(){ return sessionStorage.getItem('signalbox.token') || ''; }
function headers(){ return {'content-type':'application/json', authorization:`Bearer ${token()}`}; }
function notify(message){ toast.textContent=message; toast.classList.add('show'); setTimeout(()=>toast.classList.remove('show'),2400); }
function escape(value){ return String(value).replace(/[&<>"']/g, char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])); }
function paint(){
  let html=escape(source.value);
  html=html.replace(/(\/\/.*)$/gm,'<span class="comment">$1</span>')
    .replace(/(&quot;[^&]*?&quot;)/g,'<span class="str">$1</span>')
    .replace(/\b(model|version|enum|entity|policy|allow|action|query|caller|authorize|require|idempotency|create|update|returns|from|as|where|limit|and|or|not|true|false|null)\b/g,'<span class="kw">$1</span>')
    .replace(/\b(UUID|String|Boolean|DateTime|Int|Decimal)\b/g,'<span class="type">$1</span>');
  highlight.innerHTML=html.split('\n').map((line,index)=>`<span class="code-line" data-line="${index+1}">${line || ' '}</span>`).join('');
  highlight.scrollTop=source.scrollTop; highlight.scrollLeft=source.scrollLeft;
  document.querySelector('#save-state').textContent=source.disabled?'Source unavailable':source.value!==currentSource?'Draft saved in session':'Deployed source loaded';
}
function cursor(){ const before=source.value.slice(0,source.selectionStart).split('\n'); document.querySelector('#cursor').textContent=`Ln ${before.length}, Col ${before.at(-1).length+1}`; }
function updatePublicationControls(){
  document.querySelector('#compile').disabled=!canAdministerGovernance || source.disabled || validatedSource!==source.value || !!candidateId;
  document.querySelector('#activate').disabled=!canAdministerGovernance || !candidateId || validatedSource!==source.value;
  document.querySelector('#rollback').disabled=!canAdministerGovernance || !activePolicy?.previousVersionId;
  document.querySelector('#governance-permission').textContent=canAdministerGovernance?'Active human admin · publication enabled':'Review access · edit and validate; an active human admin must publish.';
}
function setActive(active){
  activePolicy=active;
  document.querySelector('#active-version').textContent=active?`${active.model.name} · ${active.model.version}`:'No active policy';
  document.querySelector('#active-hash').textContent=active?.model.sourceHash || 'No active policy bundle is recorded.';
  updatePublicationControls();
}
function renderDiagnostics(items=[]){
  const list=document.querySelector('#diagnostic-list'); document.querySelector('#diagnostic-count').textContent=items.length;
  list.innerHTML=items.length?items.map(item=>`<li><button data-line="${Number(item.line)}" data-column="${Number(item.column)}">${escape(item.code)} · line ${Number(item.line)}:${Number(item.column)}</button><br>${escape(item.message)}</li>`).join(''):'<li class="empty">No diagnostics.</li>';
  list.querySelectorAll('button').forEach(button=>button.addEventListener('click',()=>goTo(Number(button.dataset.line),Number(button.dataset.column))));
}
function renderPreview(value, artifacts=[]){
  const groups=[['Agents',value.agents],['Connectors',value.connectors],['Resources',value.resources],['Capabilities',value.capabilities],['Delegations',value.delegations],['Approval boundaries',value.approvalBoundaries],['Generated MCP tools',value.mcpTools],['Generated artifacts',artifacts]];
  document.querySelector('#surface-count').textContent=groups.slice(0,-1).reduce((sum,[,items])=>sum+items.length,0);
  document.querySelector('#preview-groups').classList.remove('empty-state');
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
  updatePublicationControls();
  document.querySelector('#validation-state').textContent='Validation not run'; document.querySelector('#validation-state').className='status-idle';
  document.querySelector('#diagnostic-count').textContent='—'; setDocumentState('Draft'); setCandidateState('Not compiled','Validate first, then compile an isolated policy candidate.');
}
function goTo(line,column){ const lines=source.value.split('\n'); let pos=0; for(let i=0;i<line-1;i++)pos+=lines[i].length+1; source.focus(); source.setSelectionRange(pos+column-1,pos+column-1); cursor(); }
async function api(path, body){
  if(!token()){ if(!document.querySelector('#token-dialog').open)document.querySelector('#token-dialog').showModal(); throw new Error('Access token required'); }
  const generation=sessionGeneration;
  const response=await fetch(path,{method:body===undefined?'GET':'POST',headers:headers(),...(body===undefined?{}:{body:JSON.stringify(body)})});
  const data=await response.json();
  if(generation!==sessionGeneration)throw new Error('Access token changed. Reload the current session data.');
  if(!response.ok){
    if(data.code==='SB_GOVERNANCE_ADMIN_REQUIRED'){canAdministerGovernance=false;updatePublicationControls();}
    throw new Error(data.message||`Request failed (${response.status})`);
  }
  return data;
}
async function validate(){
  if(source.disabled)return;
  const requestedSource=source.value, generation=sessionGeneration;
  candidateId=null; validatedSource=null; updatePublicationControls();
  document.querySelector('#validate').disabled=true; document.querySelector('#validation-state').textContent='Validating…';
  try{ const data=await api('/studio/api/validate',{source:requestedSource});
    if(source.value!==requestedSource || generation!==sessionGeneration)return;
    renderDiagnostics(data.diagnostics);
    if(!data.ok){ document.querySelector('#validation-state').textContent=`${data.diagnostics.length} errors`; document.querySelector('#validation-state').className='status-error'; setDocumentState('Needs attention'); switchTab('diagnostics'); return; }
    validatedSource=requestedSource; renderPreview(data.preview,data.artifacts); document.querySelector('#validation-state').textContent='Validated'; document.querySelector('#validation-state').className='status-ok'; setDocumentState('Validated','valid'); switchTab('structure');
  }catch(error){if(generation===sessionGeneration){document.querySelector('#validation-state').textContent='Validation failed';notify(error.message);}}
  finally{if(generation===sessionGeneration){document.querySelector('#validate').disabled=source.disabled;updatePublicationControls();}}
}
async function compileCandidate(){
  if(!canAdministerGovernance)return;
  if(validatedSource!==source.value){notify('Validate the current draft before compiling.');return;}
  const requestedSource=source.value, generation=sessionGeneration;
  document.querySelector('#compile').disabled=true; document.querySelector('#validation-state').textContent='Compiling candidate…';
  try{const data=await api('/studio/api/compile',{source:requestedSource});
    if(source.value!==requestedSource || generation!==sessionGeneration)return;
    renderDiagnostics(data.diagnostics);
    if(!data.ok){document.querySelector('#validation-state').textContent='Compile failed';switchTab('diagnostics');return;}
    candidateId=data.candidateId;renderPreview(data.preview,data.artifacts);document.querySelector('#validation-state').textContent='Candidate ready';setDocumentState('Candidate','candidate');setCandidateState(`${data.model.name} · ${data.model.version}`,data.model.sourceHash,true);notify('Policy candidate compiled and ready to activate');
  }catch(error){if(generation===sessionGeneration){document.querySelector('#validation-state').textContent='Compile failed';notify(error.message);}}
  finally{if(generation===sessionGeneration)updatePublicationControls();}
}
function switchTab(id){document.querySelectorAll('.inspector-tabs button[data-tab]').forEach(button=>button.classList.toggle('active',button.dataset.tab===id));document.querySelectorAll('.tab-panel').forEach(panel=>panel.classList.toggle('active',panel.id===id));}
function renderActivity(items){
  const list=document.querySelector('#activity-list');
  list.replaceChildren();
  for(const item of items){
    const row=document.createElement('li'); row.className='activity-item'; row.dataset.evidenceId=item.id;
    const timestamp=new Date(item.createdAt);
    const time=Number.isNaN(timestamp.getTime())?item.createdAt:timestamp.toLocaleString();
    const hasResult=item.result!==null && item.result!==undefined;
    const modelAction=item.result?.kind==='action';
    const operationName=operationNames[item.operationId] || item.operationId;
    const readableName=operationName.replace(/([a-z])([A-Z])/g,'$1 $2');
    const recordLabel=modelAction?'Transaction recorded':'Authorization';
    const execution=item.result?.execution;
    const executionNote=execution?.status==='SUCCEEDED' && execution.externalReference
      ? `Worker recorded success. External reference: ${execution.externalReference}`
      : execution ? `Worker status: ${execution.status}. No successful external result recorded.`
      : modelAction?'Request recorded. Worker execution is a separate step.':'This decision did not execute an external action.';
    row.innerHTML=`<div class="activity-item-header"><strong class="activity-operation">${escape(readableName)}</strong><span class="decision-badge" data-decision="${escape(item.decision)}">${recordLabel} · ${escape(item.decision)}</span><time datetime="${escape(item.createdAt)}">${escape(time)}</time></div><dl class="activity-policy"><dt>Policy bundle</dt><dd>${escape(item.policyBundleId || 'Not recorded')}</dd><dt>Source hash</dt><dd>${escape(item.policySourceHash || 'Not recorded')}</dd></dl><p class="execution-note">${executionNote}</p>${hasResult?`<details class="activity-result"><summary>Decision details</summary><pre>${escape(JSON.stringify(item.result,null,2))}</pre></details>`:'<p class="activity-no-result">No result or effect evidence recorded.</p>'}`;
    list.append(row);
  }
}
async function loadActivity(){
  const request=++activityRequest;
  const panel=document.querySelector('#activity'), status=document.querySelector('#activity-status'), refresh=document.querySelector('#refresh-activity');
  panel.setAttribute('aria-busy','true'); refresh.disabled=true;
  status.textContent='Loading recorded activity…'; status.classList.remove('error');
  document.querySelector('#activity-list').replaceChildren();
  try{
    const data=await api('/studio/api/activity');
    if(request!==activityRequest)return;
    if(!Array.isArray(data.items))throw new Error('The activity response did not contain recorded items.');
    operationNames=data.operationNames || {};
    renderActivity(data.items);
    status.textContent=data.items.length?`${data.items.length} recorded ${data.items.length===1?'action':'actions'} · refreshed ${new Date().toLocaleTimeString()}`:'No governed action evidence has been recorded for this tenant. Validating or compiling a policy does not execute an action.';
  }catch(error){if(request===activityRequest){status.textContent=`Activity unavailable: ${error.message}`;status.classList.add('error');}}
  finally{if(request===activityRequest){panel.setAttribute('aria-busy','false');refresh.disabled=false;}}
}
async function loadBootstrap(){
  const request=++bootstrapRequest;
  canAdministerGovernance=false; baselineSource=null; currentSource=''; source.value=''; source.disabled=true;
  document.querySelector('#reset-baseline').hidden=true;
  document.querySelector('#format').disabled=true; document.querySelector('#validate').disabled=true;
  document.querySelector('#surface-count').textContent='—';
  document.querySelector('#preview-groups').classList.add('empty-state');
  document.querySelector('#preview-groups').innerHTML='<p>Validate to inspect the governed surface and approval boundaries.</p>';
  document.querySelector('#diagnostic-list').innerHTML='<li class="empty">Validation has not run.</li>';
  setActive(null);resetValidation();paint();cursor();
  document.querySelector('#governance-permission').textContent='Checking publication permissions…';
  try{
    const data=await api('/studio/api/bootstrap');
    if(request!==bootstrapRequest)return;
    if(typeof data.source!=='string' || !data.source.trim())throw new Error('Deployed Signalbox policy source is unavailable.');
    currentSource=data.source; source.value=data.source; source.disabled=false;
    const saved=sessionStorage.getItem(draftKey);
    if(saved){try{const draft=JSON.parse(saved);if(draft.baseSource===currentSource && typeof draft.source==='string')source.value=draft.source;}catch{sessionStorage.removeItem(draftKey);}}
    baselineSource=typeof data.baselineSource==='string' && data.baselineSource.trim()?data.baselineSource:null;
    document.querySelector('#reset-baseline').hidden=baselineSource===null;
    canAdministerGovernance=data.permissions?.canAdministerGovernance===true;
    setActive(data.active);paint();cursor();resetValidation();
    document.querySelector('#format').disabled=false; document.querySelector('#validate').disabled=false;
    if(source.value===currentSource && data.active){setDocumentState('Active','valid');document.querySelector('#validation-state').textContent='Active';}
  }catch(error){if(request===bootstrapRequest){setDocumentState('Unavailable');document.querySelector('#governance-permission').textContent='Publication unavailable · authenticate and load the deployed policy.';notify(error.message);}}
}

source.addEventListener('input',()=>{paint();cursor();resetValidation();sessionStorage.setItem(draftKey,JSON.stringify({baseSource:currentSource,source:source.value}));});
source.addEventListener('scroll',paint);source.addEventListener('click',cursor);source.addEventListener('keyup',cursor);
source.addEventListener('keydown',event=>{if(event.key==='Tab'){event.preventDefault();source.setRangeText('  ',source.selectionStart,source.selectionEnd,'end');source.dispatchEvent(new Event('input'));}});
document.querySelector('#validate').addEventListener('click',validate);
document.querySelector('#validate-empty').addEventListener('click',validate);
document.querySelector('#compile').addEventListener('click',compileCandidate);
document.querySelector('#format').addEventListener('click',()=>{if(source.disabled)return;source.value=source.value.split('\n').map(line=>line.replace(/\s+$/,'')).join('\n').trim()+'\n';source.dispatchEvent(new Event('input'));notify('Whitespace normalized');});
document.querySelector('#reset-baseline').addEventListener('click',()=>{if(baselineSource===null)return;if(source.value!==currentSource&&!window.confirm('Replace the current policy draft with the deployed baseline?'))return;source.value=baselineSource;source.dispatchEvent(new Event('input'));source.focus();notify('Baseline loaded as a draft; active policy unchanged');});
document.querySelector('#activate').addEventListener('click',async()=>{
  if(!canAdministerGovernance || !candidateId || validatedSource!==source.value)return;
  const requestedSource=source.value, generation=sessionGeneration;
  document.querySelector('#activate').disabled=true;
  try{const data=await api('/studio/api/activate',{candidateId});
    if(generation!==sessionGeneration)return;
    candidateId=null;currentSource=requestedSource;setActive(data.active);
    if(source.value===requestedSource){validatedSource=null;sessionStorage.removeItem(draftKey);setDocumentState('Active','valid');setCandidateState('Activated',`${data.active.model.name} · ${data.active.model.version}`);document.querySelector('#validation-state').textContent='Active';}
    else{sessionStorage.setItem(draftKey,JSON.stringify({baseSource:currentSource,source:source.value}));resetValidation();}
    paint();notify('Policy candidate activated');void loadActivity();
  }catch(error){if(generation===sessionGeneration)notify(error.message);}
  finally{if(generation===sessionGeneration)updatePublicationControls();}
});
document.querySelector('#rollback').addEventListener('click',async()=>{
  if(!canAdministerGovernance || !activePolicy?.previousVersionId)return;
  const generation=sessionGeneration;document.querySelector('#rollback').disabled=true;
  try{const data=await api('/studio/api/rollback',{});if(generation!==sessionGeneration)return;setActive(data.active);resetValidation();notify('Prior policy version restored; editor draft unchanged');void loadActivity();}
  catch(error){if(generation===sessionGeneration)notify(error.message);}
  finally{if(generation===sessionGeneration)updatePublicationControls();}
});
document.querySelector('#refresh-activity').addEventListener('click',loadActivity);
for(const [id,mode] of [['show-actions','activity'],['show-policy','policy']])document.querySelector(`#${id}`).addEventListener('click',()=>{
  document.querySelector('#workspace').dataset.mode=mode;
  document.querySelector('#show-actions').setAttribute('aria-pressed',String(mode==='activity'));
  document.querySelector('#show-policy').setAttribute('aria-pressed',String(mode==='policy'));
});
document.querySelector('#configure-token').addEventListener('click',()=>document.querySelector('#token-dialog').showModal());
document.querySelector('#save-token').addEventListener('click',()=>{
  const nextToken=document.querySelector('#token').value.trim();
  if(nextToken!==token())sessionStorage.removeItem(draftKey);
  sessionStorage.setItem('signalbox.token',nextToken);document.querySelector('#token').value='';sessionGeneration++;
  notify('Access token stored for this session');void loadBootstrap();void loadActivity();
});
document.querySelectorAll('.inspector-tabs button[data-tab]').forEach(button=>button.addEventListener('click',()=>switchTab(button.dataset.tab)));
document.querySelector('#toggle-inspector').addEventListener('click',event=>{const collapsed=document.querySelector('#workspace').classList.toggle('inspector-collapsed');event.currentTarget.textContent=collapsed?'‹':'×';event.currentTarget.setAttribute('aria-label',collapsed?'Expand inspector':'Collapse inspector');});
window.addEventListener('beforeunload',event=>{if(source.value!==currentSource){event.preventDefault();event.returnValue='';}});
void loadBootstrap();void loadActivity();
