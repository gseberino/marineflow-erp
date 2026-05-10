const fs = require('fs');
const path = require('path');

const directoryToSearch = path.join(__dirname, 'src');

const variablesToAudit = [
  'supplier_name',
  'contact_phone',
  'contact_email',
  'marina_name',
  'product_name',
  'service_name',
  'display_name',
  'product_name_snapshot',
  'service_name_snapshot'
];

let results = {};
variablesToAudit.forEach(v => results[v] = { fileCount: 0, occurrences: 0 });

function walkSync(dir, filelist = []) {
  const files = fs.readdirSync(dir);
  for (const file of files) {
    const dirFile = path.join(dir, file);
    const dirent = fs.statSync(dirFile);
    if (dirent.isDirectory()) {
      filelist = walkSync(dirFile, filelist);
    } else {
      if (dirFile.endsWith('.ts') || dirFile.endsWith('.tsx')) {
        filelist.push(dirFile);
      }
    }
  }
  return filelist;
}

const allFiles = walkSync(directoryToSearch);

allFiles.forEach(file => {
  const content = fs.readFileSync(file, 'utf8');
  
  variablesToAudit.forEach(variable => {
    // Regex to find exact word matches
    const regex = new RegExp(`\\b${variable}\\b`, 'g');
    const matches = content.match(regex);
    
    if (matches && matches.length > 0) {
      results[variable].fileCount += 1;
      results[variable].occurrences += matches.length;
    }
  });
});

console.log('--- RELATÓRIO DE IMPACTO NO CÓDIGO ---');
variablesToAudit.forEach(variable => {
  console.log(`${variable}: ${results[variable].occurrences} ocorrências em ${results[variable].fileCount} arquivos`);
});
