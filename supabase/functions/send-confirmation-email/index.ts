import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
// Resend で送信者として登録済みのメールアドレスに変更してください
const FROM_ADDRESS = Deno.env.get('MAIL_FROM') ?? 'noreply@example.com';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  if (!RESEND_API_KEY) {
    return new Response(JSON.stringify({ error: 'RESEND_API_KEY is not set' }), {
      status: 500,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  let body: Record<string, string>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), {
      status: 400,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  const {
    to_email,
    to_name,
    form_title,
    submitted_at,
    form_url,
    edit_url,
    edit_deadline,
    edit_limit,
  } = body;

  // 簡易バリデーション
  if (!to_email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to_email)) {
    return new Response(JSON.stringify({ error: 'Invalid to_email' }), {
      status: 400,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  const editSection = edit_url
    ? `
      <p>回答内容の修正は以下のリンクから行えます（${edit_deadline ?? '開催日の3日前まで'}・${edit_limit ?? '回数無制限'}）。</p>
      <p><a href="${edit_url}">${edit_url}</a></p>
    `
    : '';

  const htmlBody = `
    <p>${to_name ?? 'ご回答者様'} 様</p>
    <p>「${form_title ?? 'アンケート'}」へのご回答ありがとうございました。</p>
    <p>以下の内容で受け付けました。</p>
    <ul>
      <li>受付日時: ${submitted_at ?? ''}</li>
      <li>フォームURL: <a href="${form_url ?? ''}">${form_url ?? ''}</a></li>
    </ul>
    ${editSection}
    <p>ご不明な点がございましたら、主催者へお問い合わせください。</p>
  `.trim();

  console.log('Sending email to:', to_email);
  console.log('From:', FROM_ADDRESS);
  console.log('API Key present:', !!RESEND_API_KEY);

  const resendRes = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from: FROM_ADDRESS,
      to: [to_email],
      subject: `【受付完了】${form_title ?? 'アンケート'} へのご回答`,
      html: htmlBody,
    }),
  });

  console.log('Resend response status:', resendRes.status);

  const resendData = await resendRes.json();

  console.log('Resend response data:', resendData);

  if (!resendRes.ok) {
    console.error('Resend API error:', resendData);
    return new Response(JSON.stringify({ error: resendData }), {
      status: resendRes.status,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  console.log('Email sent successfully. ID:', resendData.id);

  return new Response(JSON.stringify({ id: resendData.id }), {
    status: 200,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
});
