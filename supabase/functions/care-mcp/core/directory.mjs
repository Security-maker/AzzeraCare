// Auth account creation is outside a SQL transaction. Reserve once, never retry
// an ambiguous external result. No password, token or admin error is returned.
export async function confirmDirectory({rpc,createAdmin,initialPassword},planId){
 // Check server configuration BEFORE reserving the operation.
 if(typeof initialPassword!=='string'||initialPassword.length<12||initialPassword.length>128)throw Error('MCP_INITIAL_PASSWORD_NOT_CONFIGURED');
 const admin=createAdmin();
 const claim=await rpc('care_mcp_directory_claim',{p_id:planId});
 if(!claim.execute)return claim.result;
 const unknown={ok:false,applied:false,plan_id:planId,error:'MCP_ACCOUNT_CREATION_REQUIRES_REVIEW',outcome_unknown:true};
 let userId=null;
 try{
  const {data,error}=await admin.auth.admin.createUser({email:claim.payload.email,password:initialPassword,email_confirm:true,user_metadata:{full_name:claim.payload.full_name}});
  if(!error&&data?.user?.id)userId=data.user.id;
 }catch{/* A timeout may mean the account exists: never repeat this creation. */}
 try{
  const {data,error}=await admin.rpc('care_mcp_directory_finish',{p_id:planId,p_attempt:claim.attempt,p_user_id:userId});
  return error||!data?unknown:data;
 }catch{return unknown;}
}
