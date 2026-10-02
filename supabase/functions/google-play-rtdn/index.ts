import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { PLAY_PACKAGE, tokenHash } from "../_shared/google_play.ts";
import { syncPurchase } from "../_shared/google_play_sync.ts";
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"Content-Type":"application/json"}});
Deno.serve(async(req)=>{try{
 if(req.method!=="POST") return json({error:"Method not allowed"},405);
 const secret=Deno.env.get("GOOGLE_PLAY_RTDN_SHARED_SECRET")??""; const provided=new URL(req.url).searchParams.get("token")??"";
 if(!secret||provided!==secret) return json({error:"Unauthorized"},401);
 const url=Deno.env.get("SUPABASE_URL"), service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"); if(!url||!service) return json({error:"Server configuration is incomplete"},500);
 const envelope=await req.json(); const msg=envelope.message??{}; const messageId=String(msg.messageId??""); if(!messageId) return json({error:"Missing Pub/Sub message id"},400);
 const payload=JSON.parse(atob(String(msg.data??""))); const sub=payload.subscriptionNotification; if(!sub) return json({ok:true,ignored:true});
 const pkg=String(payload.packageName??""); const token=String(sub.purchaseToken??""); const type=Number(sub.notificationType??0); if(pkg!==PLAY_PACKAGE||!token) return json({ok:true,ignored:true});
 const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}}); const hash=tokenHash(token);
 const {data:existing}=await admin.from("google_play_rtdn_events").select("status").eq("message_id",messageId).maybeSingle(); if(existing?.status==="processed") return json({ok:true,duplicate:true});
 await admin.from("google_play_rtdn_events").upsert({message_id:messageId,publish_time:msg.publishTime??null,package_name:pkg,notification_type:type,purchase_token_hash:hash,event_time_millis:Number(payload.eventTimeMillis??0)||null,status:"received"},{onConflict:"message_id"});
 try { const result=await syncPurchase(admin,{packageName:pkg,purchaseToken:token}); await admin.from("google_play_rtdn_events").update({status:"processed",processed_at:new Date().toISOString(),error_code:null}).eq("message_id",messageId); return json({ok:true,...result}); }
 catch(e){console.error(e);await admin.from("google_play_rtdn_events").update({status:"failed",processed_at:new Date().toISOString(),error_code:"SYNC_FAILED"}).eq("message_id",messageId);return json({error:"Subscription synchronization failed"},500);}
}catch(e){console.error(e);return json({error:"Invalid RTDN request"},400);}});
