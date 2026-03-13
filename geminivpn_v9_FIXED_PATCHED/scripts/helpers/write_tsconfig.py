import sys, json
cfg = {
  "compilerOptions": {
    "target": "ES2020", "module": "commonjs", "lib": ["ES2020"],
    "outDir": "./dist", "rootDir": "./src",
    "strict": False, "esModuleInterop": True, "skipLibCheck": True,
    "forceConsistentCasingInFileNames": True, "resolveJsonModule": True,
    "declaration": False, "sourceMap": False, "moduleResolution": "node",
    "allowSyntheticDefaultImports": True, "experimentalDecorators": True,
    "noImplicitAny": False, "strictNullChecks": False,
    "noUnusedLocals": False, "noUnusedParameters": False, "noImplicitReturns": False,
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"], "@controllers/*": ["src/controllers/*"],
      "@services/*": ["src/services/*"], "@middleware/*": ["src/middleware/*"],
      "@utils/*": ["src/utils/*"], "@types/*": ["src/types/*"]
    }
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "prisma"]
}
dest = sys.argv[1] if len(sys.argv) > 1 else '/tmp/tsconfig.json'
with open(dest, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
print("tsconfig.json written to", dest)
