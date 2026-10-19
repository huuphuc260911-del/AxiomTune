#!/usr/bin/env python3
"""
Axiom — GitHub Remote Tree Inspector
------------------------------------
Nếu mày đéo biết mình đã upload những file nào lên GitHub rồi (do bị lỗi
trùng tên như vừa nãy), chạy con script này. Nó sẽ gọi API GitHub để lấy
cây thư mục thực tế (remote tree) và in ra màn hình dưới dạng cây ASCII.
Giúp mày check xem còn thiếu file nào trước khi build.
"""

import sys
import json
import urllib.request
import urllib.error
from collections import defaultdict

class GitHubTreeInspector:
    def __init__(self, owner: str, repo: str, branch: str = "main", token: str = ""):
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.token = token
        self.tree_data = {}

    def _api_request(self, url: str) -> dict:
        req = urllib.request.Request(url)
        req.add_header("Accept", "application/vnd.github.v3+json")
        req.add_header("User-Agent", "Axiom-Inspector")
        if self.token:
            req.add_header("Authorization", f"token {self.token}")
        
        try:
            with urllib.request.urlopen(req) as response:
                return json.loads(response.read().decode())
        except urllib.error.HTTPError as e:
            if e.code == 404:
                print(f"❌ 404: Không tìm thấy repo {self.owner}/{self.repo} (hoặc branch {self.branch})")
                sys.exit(1)
            print(f"❌ Lỗi API: {e.code} - {e.reason}")
            sys.exit(1)
        except Exception as e:
            print(f"❌ Lỗi kết nối: {e}")
            sys.exit(1)

    def fetch_tree(self):
        url = f"https://api.github.com/repos/{self.owner}/{self.repo}/git/trees/{self.branch}?recursive=1"
        print(f"🔍 Đang quét cây thư mục: {self.owner}/{self.repo} @ {self.branch}...")
        
        data = self._api_request(url)
        if "tree" not in data:
            print("❌ Không lấy được dữ liệu tree.")
            sys.exit(1)
            
        for item in data["tree"]:
            if item["type"] == "blob":  # Chỉ lấy file, bỏ qua thư mục (nó tự suy ra)
                self.tree_data[item["path"]] = item.get("size", 0)

    def build_ascii_tree(self) -> str:
        if not self.tree_data:
            return "(Trống rỗng)"
            
        # Tạo cấu trúc dict lồng nhau
        nested = defaultdict(dict)
        for path, size in self.tree_data.items():
            parts = path.split("/")
            current = nested
            for part in parts[:-1]:
                current = current.setdefault(part, {})
            current[parts[-1]] = size

        def _render(node, prefix=""):
            lines = []
            items = sorted(node.items())
            for i, (name, value) in enumerate(items):
                is_last = i == len(items) - 1
                connector = "└── " if is_last else "├── "
                
                if isinstance(value, dict):
                    lines.append(f"{prefix}{connector}{name}/")
                    new_prefix = prefix + ("    " if is_last else "│   ")
                    lines.extend(_render(value, new_prefix))
                else:
                    size_str = f" ({value} bytes)" if value > 0 else ""
                    lines.append(f"{prefix}{connector}{name}{size_str}")
            return lines

        return "\n".join(_render(nested))

    def check_required_files(self):
        required = [
            "project.yml",
            ".github/workflows/build.yml",
            "Sources/Info.plist",
            "Sources/AxiomTuneApp.swift"
        ]
        
        print("\n📋 KIỂM TRA FILE BẮT BUỘC:")
        missing = 0
        for req in required:
            if req in self.tree_data:
                print(f"  ✅ {req}")
            else:
                print(f"  ❌ THIẾU: {req}")
                missing += 1
                
        if missing > 0:
            print(f"\n⚠️  Mày còn thiếu {missing} file. Đéo build được đâu!")
        else:
            print("\n🎉 ĐỦ FILE RỒI! GitHub Actions sẽ build thành công.")


if __name__ == "__main__":
    # Mày có thể sửa cứng thông tin user/repo của mày ở đây
    OWNER = "huuphuc260911-del"
    REPO = "AxiomTune"
    BRANCH = "main"
    
    inspector = GitHubTreeInspector(OWNER, REPO, BRANCH)
    inspector.fetch_tree()
    
    print("\n📁 CẤU TRÚC REPO HIỆN TẠI:")
    print(inspector.build_ascii_tree())
    
    inspector.check_required_files()
