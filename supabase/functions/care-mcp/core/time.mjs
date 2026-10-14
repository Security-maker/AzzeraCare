const formatter=new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Paris',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'});
export const paris=iso=>formatter.format(new Date(iso)).replace(' ','T');
export function resolveParis(local,offset){
 if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(local))throw Error('LOCAL_DATE_INVALID');
 const target=local.length===16?local+':00':local, nominal=Date.parse(target+'Z');
 const options=[60,120].map(m=>new Date(nominal-m*60000).toISOString()).filter(i=>paris(i)===target);
 if(!options.length)throw Error('PARIS_TIME_DOES_NOT_EXIST');
 if(offset){const selected=target+offset;if(!options.some(i=>Date.parse(i)===Date.parse(selected)))throw Error('PARIS_OFFSET_INVALID');return new Date(selected).toISOString();}
 if(options.length!==1)throw Error('PARIS_TIME_AMBIGUOUS_CHOOSE_+01:00_OR_+02:00');
 return options[0];
}
export function periodRange(date,period){
 if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||new Date(date+'T00:00Z').toISOString().slice(0,10)!==date)throw Error('DATE_INVALID');
 let start=new Date(date+'T00:00Z'),end;
 if(period==='week')start.setUTCDate(start.getUTCDate()-(start.getUTCDay()+6)%7);
 if(period==='month')start.setUTCDate(1);
 end=new Date(start);if(period==='month')end.setUTCMonth(end.getUTCMonth()+1);else end.setUTCDate(end.getUTCDate()+(period==='week'?7:1));
 return {from:resolveParis(start.toISOString().slice(0,10)+'T00:00'),to:resolveParis(end.toISOString().slice(0,10)+'T00:00')};
}
