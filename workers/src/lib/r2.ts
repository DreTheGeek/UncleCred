import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";

const r2 = new S3Client({
  region: "auto",
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: { accessKeyId: process.env.R2_ACCESS_KEY_ID!, secretAccessKey: process.env.R2_SECRET_ACCESS_KEY! },
});
const Bucket = process.env.R2_BUCKET!;

export async function putObject(Key: string, Body: Buffer | string, ContentType: string) {
  await r2.send(new PutObjectCommand({ Bucket, Key, Body, ContentType }));
  return `${process.env.R2_PUBLIC_BASE_URL}/${Key}`;
}
export async function getObject(Key: string) {
  const res = await r2.send(new GetObjectCommand({ Bucket, Key }));
  return Buffer.from(await res.Body!.transformToByteArray());
}
