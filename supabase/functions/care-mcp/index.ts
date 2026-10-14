import {McpServer} from 'npm:@modelcontextprotocol/sdk@1.32.1/server/mcp.js';
import {WebStandardStreamableHTTPServerTransport} from 'npm:@modelcontextprotocol/sdk@1.32.1/server/webStandardStreamableHttp.js';
import {z} from 'npm:zod@3.25.76';
import {createClient} from 'npm:@supabase/supabase-js@2.116.0';
import {makeHandler} from './core/handler.mjs';
Deno.serve(makeHandler({McpServer,Transport:WebStandardStreamableHTTPServerTransport,z,createClient,env:name=>Deno.env.get(name)}));
