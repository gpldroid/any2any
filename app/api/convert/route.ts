import {NextResponse} from "next/server";
import {promises as fs} from "fs";
import {tmpdir} from "os";
import path from "path";
import {randomUUID} from "crypto";
import {spawn} from "child_process";
import {createClient} from "@/lib/supabase/server";

export const runtime="nodejs";
export const dynamic="force-dynamic";

const mimeByFormat:Record<string,string>={
  ai:"application/postscript",apng:"image/apng",avif:"image/avif",bmp:"image/bmp",
  dds:"image/vnd-ms.dds",dib:"image/bmp",eps:"application/postscript",gif:"image/gif",
  hdr:"image/vnd.radiance",heic:"image/heic",heif:"image/heif",ico:"image/x-icon",
  jp2:"image/jp2",jpe:"image/jpeg",jpeg:"image/jpeg",pdf:"application/pdf",
  png:"image/png",psd:"image/vnd.adobe.photoshop",raw:"application/octet-stream",
  svg:"image/svg+xml",tga:"image/x-tga",tiff:"image/tiff",wbmp:"image/vnd.wap.wbmp",
  webp:"image/webp"
};

function runConvert(input:string,output:string){
  return new Promise<void>((resolve,reject)=>{
    const binary=process.env.IMAGEMAGICK_BIN||"convert";
    const p=spawn(binary,[input,output],{stdio:["ignore","ignore","pipe"]});
    let err="";
    p.stderr.on("data",d=>err+=d.toString());
    p.on("error",reject);
    p.on("close",code=>code===0?resolve():reject(new Error(err||"ImageMagick conversion failed")));
  });
}

export async function POST(req:Request){
  const form=await req.formData();
  const file=form.get("file");
  const format=String(form.get("format")||"").trim().toLowerCase();

  if(!(file instanceof File)||!mimeByFormat[format])
    return new NextResponse("Invalid file or format",{status:400});

  const max=Number(process.env.NEXT_PUBLIC_MAX_UPLOAD_MB||25)*1024*1024;
  if(!Number.isFinite(max)||file.size<=0||file.size>max)
    return new NextResponse("File too large or empty",{status:413});

  const supabase=await createClient();
  const {data:formatRow,error:formatError}=await supabase
    .from("converter_formats")
    .select("slug,enabled")
    .eq("slug",format)
    .maybeSingle();

  if(formatError)
    return new NextResponse("Supabase format lookup failed",{status:503});
  if(!formatRow?.enabled)
    return new NextResponse("Conversion format is disabled",{status:404});

  const id=randomUUID();
  const dir=path.join(tmpdir(),"any2any",id);
  const input=path.join(dir,"input");
  const output=path.join(dir,"output."+format);
  await fs.mkdir(dir,{recursive:true});

  let jobId:string|undefined;

  try{
    await fs.writeFile(input,Buffer.from(await file.arrayBuffer()));

    const {data:{user}}=await supabase.auth.getUser();
    const {data:job,error:jobError}=await supabase.from("conversions").insert({
      user_id:user?.id??null,
      source_name:file.name.slice(0,255),
      source_format:path.extname(file.name).slice(1).toLowerCase()||"unknown",
      target_format:format,
      status:"processing",
      input_size:file.size
    }).select("id").single();

    if(jobError) throw new Error(jobError.message);
    jobId=job.id;

    await runConvert(input,output);
    const body=await fs.readFile(output);

    const {error:updateError}=await supabase.from("conversions").update({
      status:"completed",
      output_size:body.length,
      completed_at:new Date().toISOString()
    }).eq("id",jobId);

    if(updateError) throw new Error(updateError.message);
    await supabase.rpc("increment_convert_counter");

    return new NextResponse(body,{
      headers:{
        "Content-Type":mimeByFormat[format],
        "Content-Disposition":`attachment; filename="converted.${format}"`,
        "Cache-Control":"no-store"
      }
    });
  }catch(e){
    if(jobId){
      await supabase.from("conversions").update({
        status:"failed",
        error_message:e instanceof Error?e.message:"Conversion failed"
      }).eq("id",jobId);
    }
    return new NextResponse(e instanceof Error?e.message:"Conversion failed",{status:500});
  }finally{
    await fs.rm(dir,{recursive:true,force:true});
  }
}
