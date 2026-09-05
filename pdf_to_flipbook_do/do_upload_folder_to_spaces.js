const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const fs = require('fs');
const path = require('path');
const https = require('https');

async function uploadFolder() {
    console.log('🚀 Starting folder upload to Digital Ocean Spaces...\n');

    // Configuration
    const config = {
        accessKeyId: process.env.DO_ACCESS_KEY,
        secretAccessKey: process.env.DO_SECRET_KEY,
        endpoint: process.env.DO_ENDPOINT || 'https://nyc3.digitaloceanspaces.com',
        region: process.env.DO_REGION || 'us-east-1',
        bucket: process.env.DO_BUCKET,
        folder: process.env.DO_FOLDER || 'uploads',
        cdnEndpoint: process.env.DO_CDN_ENDPOINT || '',
        apiToken: process.env.DO_API_TOKEN || '',
        cdnId: process.env.DO_CDN_ID || ''
    };

    console.log('Configuration:');
    console.log(`- Bucket: ${config.bucket}`);
    console.log(`- Endpoint: ${config.endpoint}`);
    console.log(`- Folder: ${config.folder}`);
    console.log(`- Region: ${config.region}`);
    if (config.cdnEndpoint) console.log(`- CDN Endpoint: ${config.cdnEndpoint}`);
    if (config.cdnId) console.log(`- CDN ID: ${config.cdnId}`);
    console.log('');

    // Create S3 client
    const s3Client = new S3Client({
        endpoint: config.endpoint,
        forcePathStyle: false,
        region: config.region,
        credentials: {
            accessKeyId: config.accessKeyId,
            secretAccessKey: config.secretAccessKey
        }
    });

    // Get current directory
    const currentDir = process.cwd();
    console.log(`📁 Current directory: ${currentDir}\n`);

    // Collect all files
    const files = [];
    
    function collectFiles(dir, basePath = '') {
        const items = fs.readdirSync(dir);
        
        for (const item of items) {
            const fullPath = path.join(dir, item);
            const relativePath = basePath ? path.join(basePath, item) : item;
            
            // Skip hidden files and common directories
            if (item.startsWith('.') || item === 'node_modules' || item === '.git') {
                continue;
            }
            
            if (fs.statSync(fullPath).isDirectory()) {
                collectFiles(fullPath, relativePath);
            } else {
                files.push({
                    localPath: fullPath,
                    relativePath: relativePath,
                    key: config.folder ? `${config.folder}/${relativePath}` : relativePath
                });
            }
        }
    }

    collectFiles(currentDir);
    
    if (files.length === 0) {
        console.log('❌ No files found in current directory');
        process.exit(1);
    }

    console.log(`📊 Found ${files.length} files to upload\n`);
    
    let uploadedCount = 0;
    const failedFiles = [];
    const uploadedFiles = [];

    // Upload files
    for (let i = 0; i < files.length; i++) {
        const file = files[i];
        
        try {
            process.stdout.write(`[${i + 1}/${files.length}] 📤 ${file.relativePath}... `);
            
            const fileContent = fs.readFileSync(file.localPath);
            
            // Determine content type
            const ext = path.extname(file.localPath).toLowerCase();
            let contentType = 'application/octet-stream';
            
            if (ext === '.html' || ext === '.htm') contentType = 'text/html';
            else if (ext === '.css') contentType = 'text/css';
            else if (ext === '.js') contentType = 'application/javascript';
            else if (ext === '.json') contentType = 'application/json';
            else if (ext === '.png') contentType = 'image/png';
            else if (ext === '.jpg' || ext === '.jpeg') contentType = 'image/jpeg';
            else if (ext === '.gif') contentType = 'image/gif';
            else if (ext === '.svg') contentType = 'image/svg+xml';
            else if (ext === '.txt' || ext === '.md') contentType = 'text/plain';
            else if (ext === '.pdf') contentType = 'application/pdf';
            
            const params = {
                Bucket: config.bucket,
                Key: file.key,
                Body: fileContent,
                ContentType: contentType,
                ACL: 'public-read',
                Metadata: {
                    'uploaded-from': 'folder-upload-script',
                    'x-amz-meta-version': Date.now().toString()
                }
            };
            
            await s3Client.send(new PutObjectCommand(params));
            
            uploadedCount++;
            uploadedFiles.push(file.key);
            
            console.log(`✅`);
            
        } catch (error) {
            console.log(`❌ ${error.message}`);
            failedFiles.push({ file: file.relativePath, error: error.message });
        }
    }

    console.log(`\n📊 Upload Summary:`);
    console.log(`   ✅ Successfully uploaded: ${uploadedCount}/${files.length}`);
    console.log(`   ❌ Failed: ${failedFiles.length}`);
    
    if (uploadedFiles.length > 0) {
        const spaceUrl = config.endpoint.replace('https://', `https://${config.bucket}.`);
        const baseUrl = config.cdnEndpoint ? config.cdnEndpoint : `${spaceUrl}/${config.folder}`;
        
        console.log(`\n🌐 Files available at: ${baseUrl}/`);
        console.log(`   Example: ${baseUrl}/${uploadedFiles[0]}`);
        
        // Save URLs
        fs.writeFileSync('uploaded_urls.txt', 
            `Upload: ${new Date().toISOString()}\n` +
            `Base URL: ${baseUrl}/\n\n` +
            uploadedFiles.map(f => `${baseUrl}/${f}`).join('\n')
        );
        console.log(`📄 URLs saved to: uploaded_urls.txt`);
    }

    // CDN Purge
    if (config.apiToken && config.cdnId && uploadedFiles.length > 0) {
        console.log('\n🔄 Purging CDN cache...');
        
        try {
            const purgeBody = JSON.stringify({ files: uploadedFiles });
            
            await new Promise((resolve, reject) => {
                const req = https.request({
                    method: "DELETE",
                    hostname: "api.digitalocean.com",
                    path: `/v2/cdn/endpoints/${config.cdnId}/cache`,
                    headers: {
                        "Authorization": `Bearer ${config.apiToken}`,
                        "Content-Type": "application/json"
                    }
                }, (res) => {
                    if (res.statusCode === 204 || res.statusCode === 200) {
                        console.log('✅ CDN cache purged');
                        resolve(true);
                    } else {
                        console.log(`⚠️ CDN purge status: ${res.statusCode}`);
                        resolve(false);
                    }
                });
                
                req.on('error', (error) => {
                    console.log(`⚠️ CDN purge error: ${error.message}`);
                    resolve(false);
                });
                
                req.write(purgeBody);
                req.end();
            });
        } catch (error) {
            console.log(`⚠️ CDN purge failed: ${error.message}`);
        }
    }
    
    if (failedFiles.length > 0) {
        console.log('\n❌ Failed files:');
        failedFiles.forEach(f => console.log(`   - ${f.file}`));
    }
}

uploadFolder().catch(error => {
    console.error('❌ Upload failed:', error);
    process.exit(1);
});
